import { drizzle as drizzleNode } from 'drizzle-orm/node-postgres';
import { drizzle as drizzleHttp } from 'drizzle-orm/neon-http';
import { neon } from '@neondatabase/serverless';
import pg from 'pg';
import * as schema from './schema';

/**
 * Dos clientes, deliberadamente (ARQUITECTURA.md §3).
 *
 *   · HTTP (neon-http) — para lecturas de página en el despliegue `web`.
 *     Sin conexión persistente, ideal para un contenedor que escala a
 *     cero.
 *   · TCP (node-postgres) — para el `worker` y para las rutas SSE.
 *     `LISTEN/NOTIFY` NO existe sobre el driver HTTP: requiere una
 *     conexión real y sostenida.
 *
 * Elegir uno solo obligaría a sacrificar el bus de eventos o a mantener
 * un pool abierto en un proceso que se apaga solo.
 */

function connectionString(): string {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error('DATABASE_URL no está definida.');
  return url;
}

let httpDb: ReturnType<typeof drizzleHttp<typeof schema>> | null = null;

/** Cliente HTTP para lecturas sin estado. */
export function db() {
  if (!httpDb) httpDb = drizzleHttp(neon(connectionString()), { schema });
  return httpDb;
}

let pool: pg.Pool | null = null;

export function pgPool(): pg.Pool {
  if (!pool) {
    pool = new pg.Pool({
      connectionString: connectionString(),
      max: Number(process.env.PG_POOL_MAX ?? 5),
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 10_000,
    });
    // Un error en una conexión ociosa no debe derribar el proceso.
    pool.on('error', (err) => console.error('[pg] error en conexión ociosa:', err.message));
  }
  return pool;
}

let tcpDb: ReturnType<typeof drizzleNode<typeof schema>> | null = null;

/** Cliente TCP: transacciones, `LISTEN/NOTIFY` y bloqueos de aviso. */
export function dbTcp() {
  if (!tcpDb) tcpDb = drizzleNode(pgPool(), { schema });
  return tcpDb;
}

export { schema };
