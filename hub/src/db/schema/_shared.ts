import { numeric, timestamp, uuid } from 'drizzle-orm/pg-core';
import { v7 as uuidv7 } from 'uuid';

/**
 * Convenciones transversales del esquema (ARQUITECTURA.md §5.1).
 *
 * Las claves primarias son UUID v7: ordenables en el tiempo, con buena
 * localidad de índice y generadas en la aplicación, de modo que no
 * dependemos de extensiones de PostgreSQL ni de una ida y vuelta a la
 * base de datos para conocer el identificador.
 */
export const pk = () =>
  uuid('id')
    .primaryKey()
    .$defaultFn(() => uuidv7());

export const createdAt = () =>
  timestamp('created_at', { withTimezone: true }).notNull().defaultNow();

export const updatedAt = () =>
  timestamp('updated_at', { withTimezone: true }).notNull().defaultNow();

/**
 * Importes monetarios. `numeric(20,4)` — nunca coma flotante.
 *
 * Cuatro decimales cubren la aritmética de intereses sin acumular error;
 * el redondeo a la unidad mínima de la divisa se aplica en la capa de
 * presentación. Drizzle devuelve `string`, que es exactamente lo que
 * necesita Decimal.js para operar sin pérdida.
 */
export const money = (name: string) => numeric(name, { precision: 20, scale: 4 });

/** Tasas de cambio y tipos de interés: más escala, mismo criterio exacto. */
export const rate = (name: string) => numeric(name, { precision: 20, scale: 10 });
