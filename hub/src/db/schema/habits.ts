import { date, index, integer, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';
import { habitLogState } from './enums';
import { userRef } from './identity';
import { createdAt, pk, updatedAt } from './_shared';

export const habits = pgTable('habits', {
  id: pk(),
  userId: userRef(),
  name: text('name').notNull(),
  description: text('description'),
  /** Objetivo de cumplimiento semanal; alimenta el gradiente del mapa de calor. */
  targetPerWeek: integer('target_per_week').notNull().default(7),
  color: text('color').notNull().default('#38bdf8'),
  position: integer('position').notNull().default(0),
  archivedAt: timestamp('archived_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [index('habits_user_idx').on(t.userId, t.archivedAt)]);

/**
 * Registro diario de hábitos.
 *
 * `logDate` es `date`, no `timestamptz`: un hábito pertenece a un día
 * civil en la zona del usuario, no a un instante. El día se resuelve al
 * escribir, de modo que la consulta del mapa de calor no arrastra
 * conversiones de zona horaria.
 *
 * El estado `skipped` es lo que distingue este motor de rachas de un
 * contador binario: congela la racha acumulada sin restablecerla a cero.
 */
export const habitLogs = pgTable('habit_logs', {
  id: pk(),
  userId: userRef(),
  habitId: uuid('habit_id').notNull().references(() => habits.id, { onDelete: 'cascade' }),
  logDate: date('log_date', { mode: 'string' }).notNull(),
  state: habitLogState('state').notNull(),
  note: text('note'),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [
  uniqueIndex('habit_logs_habit_date_key').on(t.habitId, t.logDate),
  index('habit_logs_user_date_idx').on(t.userId, t.logDate),
]);
