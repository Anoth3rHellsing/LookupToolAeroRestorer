import { index, integer, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';
import { userRef } from './identity';
import { createdAt, pk, updatedAt } from './_shared';

export const subjects = pgTable('subjects', {
  id: pk(),
  userId: userRef(),
  name: text('name').notNull(),
  color: text('color').notNull().default('#a78bfa'),
  archivedAt: timestamp('archived_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [index('subjects_user_idx').on(t.userId, t.archivedAt)]);

export const topics = pgTable('topics', {
  id: pk(),
  userId: userRef(),
  subjectId: uuid('subject_id').notNull().references(() => subjects.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  position: integer('position').notNull().default(0),
  completedAt: timestamp('completed_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [index('topics_subject_idx').on(t.subjectId, t.position)]);

/**
 * Sesión Pomodoro (ARQUITECTURA.md §12.3).
 *
 * `startedAt` absoluto es TODO el mecanismo. El tiempo restante nunca se
 * lleva en un contador que el navegador pueda suspender: se calcula como
 * `plannedMinutes - (now - startedAt)` cada vez que la pestaña recupera
 * el foco. Así el temporizador es correcto por construcción, suspenda el
 * sistema operativo lo que quiera.
 *
 * La v1 proponía un Web Worker para evitar la suspensión; iOS suspende
 * los workers de pestañas en segundo plano igual que el hilo principal,
 * de modo que no resolvía el problema. Este diseño lo disuelve.
 */
export const studySessions = pgTable('study_sessions', {
  id: pk(),
  userId: userRef(),
  subjectId: uuid('subject_id').references(() => subjects.id, { onDelete: 'set null' }),
  topicId: uuid('topic_id').references(() => topics.id, { onDelete: 'set null' }),
  taskId: uuid('task_id'),
  startedAt: timestamp('started_at', { withTimezone: true }).notNull(),
  plannedMinutes: integer('planned_minutes').notNull().default(25),
  /** Nulo mientras la sesión sigue viva; lo fija el cierre o el abandono. */
  endedAt: timestamp('ended_at', { withTimezone: true }),
  completedMinutes: integer('completed_minutes'),
  createdAt: createdAt(),
}, (t) => [
  index('study_sessions_user_started_idx').on(t.userId, t.startedAt),
  index('study_sessions_open_idx').on(t.userId, t.endedAt),
]);
