import { sql } from 'drizzle-orm';
import { dbTcp } from '../db/client';
import { jobRuns } from '../db/schema';
import { localHour } from '../lib/time';

/**
 * Planificador del despliegue `worker` (ARQUITECTURA.md §2.2).
 *
 * Este proceso es la razón de que el `worker` viva en un Reserved VM y no
 * en Autoscale: un contenedor que escala a cero no ejecuta temporizadores,
 * y ése era el defecto capital de la v1.
 */

export interface Job {
  name: string;
  /** Devuelve true si corresponde ejecutar en este instante. */
  due(now: Date): boolean;
  run(): Promise<{ rowsAffected?: number; detail?: Record<string, unknown> }>;
}

/**
 * Ejecuta un trabajo bajo bloqueo de aviso y deja constancia en
 * `job_runs`.
 *
 * El bloqueo es de sesión y se libera explícitamente. Aunque hoy sólo hay
 * un `worker`, un reinicio durante un solapamiento produciría doble
 * ingesta sin él.
 */
export async function runJob(job: Job): Promise<void> {
  const db = dbTcp();
  const lockKey = hashName(job.name);

  const [lock] = await db.execute<{ acquired: boolean }>(
    sql`select pg_try_advisory_lock(${lockKey}) as acquired`,
  ).then((r) => (r as unknown as { rows: { acquired: boolean }[] }).rows ?? []);

  if (!lock?.acquired) {
    console.warn(`[worker] ${job.name}: ya en ejecución, se omite este ciclo.`);
    return;
  }

  const [run] = await db
    .insert(jobRuns)
    .values({ jobName: job.name, status: 'running' })
    .returning({ id: jobRuns.id });

  const started = Date.now();
  try {
    const result = await job.run();
    await db
      .update(jobRuns)
      .set({
        status: 'succeeded',
        finishedAt: new Date(),
        rowsAffected: result.rowsAffected ?? 0,
        detail: result.detail,
      })
      .where(sql`${jobRuns.id} = ${run!.id}`);
    console.info(`[worker] ${job.name}: correcto en ${Date.now() - started} ms.`);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await db
      .update(jobRuns)
      .set({ status: 'failed', finishedAt: new Date(), error: message })
      .where(sql`${jobRuns.id} = ${run!.id}`);
    // Un trabajo que falla NO derriba el planificador: los demás deben
    // seguir corriendo, y el vigía de obsolescencia se encargará de que
    // el fallo sea visible en la interfaz.
    console.error(`[worker] ${job.name}: fallo — ${message}`);
  } finally {
    await db.execute(sql`select pg_advisory_unlock(${lockKey})`);
  }
}

/** Clave estable de 32 bits a partir del nombre del trabajo. */
function hashName(name: string): number {
  let h = 2166136261;
  for (let i = 0; i < name.length; i += 1) {
    h ^= name.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h | 0;
}

// ── Predicados de cadencia ────────────────────────────────────────────

export function everyMinutes(minutes: number): (now: Date) => boolean {
  return (now) => Math.floor(now.getTime() / 60000) % minutes === 0;
}

/** Hora local exacta en `America/Bogota`, no en UTC. */
export function atLocalHour(...hours: number[]): (now: Date) => boolean {
  return (now) => now.getUTCMinutes() < 1 && hours.includes(localHour(now));
}

/**
 * Ventana de mercado global para el oro: de lunes a viernes.
 * Fuera de ella no se consume cuota del proveedor.
 */
export function duringMarketHours(minutes: number): (now: Date) => boolean {
  const cada = everyMinutes(minutes);
  return (now) => {
    const day = now.getUTCDay();
    if (day === 6) return false;
    if (day === 0 && now.getUTCHours() < 22) return false;
    if (day === 5 && now.getUTCHours() >= 22) return false;
    return cada(now);
  };
}
