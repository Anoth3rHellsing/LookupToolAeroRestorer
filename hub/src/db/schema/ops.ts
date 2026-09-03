import { bigserial, index, integer, jsonb, pgTable, text, timestamp } from 'drizzle-orm/pg-core';
import { jobStatus } from './enums';
import { userRef } from './identity';
import { createdAt, pk } from './_shared';

/**
 * Bus de eventos (ARQUITECTURA.md §2.1).
 *
 * `NOTIFY` es efímero: si el canal se cae, el mensaje se pierde. Esta
 * tabla es el registro durable que hace correcto al sistema — el cliente
 * SSE guarda el último `id` recibido y, al reconectar, recupera todo lo
 * ocurrido durante la desconexión. El `bigserial` es deliberado: hace
 * falta un cursor monótono, no un identificador aleatorio.
 */
export const events = pgTable('events', {
  id: bigserial('id', { mode: 'number' }).primaryKey(),
  userId: userRef(),
  channel: text('channel').notNull(),
  payload: jsonb('payload').$type<Record<string, unknown>>().notNull(),
  createdAt: createdAt(),
}, (t) => [index('events_user_id_idx').on(t.userId, t.id)]);

/**
 * Registro de ejecuciones del planificador (§13.1).
 *
 * Sin esto, el modo de fallo característico del sistema es el peor
 * posible: datos obsoletos presentados como actuales.
 *
 * No lleva `userRef`: es infraestructura del proceso, no dato de negocio,
 * y debe sobrevivir al borrado de un usuario para poder auditarse.
 */
export const jobRuns = pgTable('job_runs', {
  id: pk(),
  jobName: text('job_name').notNull(),
  status: jobStatus('status').notNull(),
  startedAt: timestamp('started_at', { withTimezone: true }).notNull().defaultNow(),
  finishedAt: timestamp('finished_at', { withTimezone: true }),
  rowsAffected: integer('rows_affected'),
  error: text('error'),
  /** Origen efectivo del dato: revela cuándo se está sirviendo el respaldo. */
  detail: jsonb('detail').$type<Record<string, unknown>>(),
}, (t) => [
  index('job_runs_name_started_idx').on(t.jobName, t.startedAt),
  index('job_runs_status_idx').on(t.status),
]);
