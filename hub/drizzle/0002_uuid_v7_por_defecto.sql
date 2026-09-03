-- Valor por defecto de las claves primarias en el motor.
--
-- Drizzle genera el UUID en la aplicación mediante `$defaultFn`, lo cual
-- evita una ida y vuelta a la base de datos y es el camino correcto en
-- caliente. Pero `$defaultFn` NO emite un DEFAULT en el SQL: cualquier
-- inserción que no pase por Drizzle —una consola de administración, una
-- siembra, un trabajo en SQL crudo del worker— fallaba con «null value in
-- column id».
--
-- La generación en la aplicación se conserva; esto es la red de
-- seguridad, coherente con el criterio de que las invariantes viven en el
-- motor y no sólo en el código que hoy sabemos que existe.
--
-- Se implementa UUID v7 y no `gen_random_uuid()` (que es v4) para no
-- perder la propiedad que motivó la elección: el orden temporal, y con él
-- la localidad de índice en inserciones secuenciales.

CREATE OR REPLACE FUNCTION uuid_generate_v7() RETURNS uuid AS $$
DECLARE
  ts_ms bigint := (extract(epoch FROM clock_timestamp()) * 1000)::bigint;
  b bytea;
BEGIN
  -- 6 bytes de marca de tiempo Unix en milisegundos (big-endian) seguidos
  -- de 10 bytes aleatorios. La aleatoriedad se toma de gen_random_uuid(),
  -- que es interna desde PostgreSQL 13, para no exigir la extensión
  -- pgcrypto en el proveedor gestionado.
  b := substring(int8send(ts_ms) FROM 3 FOR 6)
       || substring(uuid_send(gen_random_uuid()) FROM 1 FOR 10);

  -- Versión 7 en los cuatro bits altos del séptimo byte.
  b := set_byte(b, 6, (get_byte(b, 6) & 15) | 112);
  -- Variante RFC 4122 (10xx) en los dos bits altos del noveno byte.
  b := set_byte(b, 8, (get_byte(b, 8) & 63) | 128);

  RETURN encode(b, 'hex')::uuid;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- Se aplica a toda clave primaria uuid del esquema. Se recorre el
-- catálogo en lugar de enumerar cuarenta tablas a mano: así una tabla
-- futura que olvide su DEFAULT queda cubierta con sólo reejecutar esto.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.relname AS tabla, a.attname AS columna
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_index i ON i.indrelid = c.oid AND i.indisprimary
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY (i.indkey)
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND a.atttypid = 'uuid'::regtype
      AND i.indnatts = 1
  LOOP
    EXECUTE format(
      'ALTER TABLE %I ALTER COLUMN %I SET DEFAULT uuid_generate_v7()',
      r.tabla, r.columna);
  END LOOP;
END $$;
