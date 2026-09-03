import { boolean, index, jsonb, numeric, pgTable, text, timestamp, uniqueIndex } from 'drizzle-orm/pg-core';
import { taskStatus } from './enums';
import { userRef } from './identity';
import { createdAt, pk, updatedAt } from './_shared';

/**
 * Tareas (ARQUITECTURA.md §8.1).
 *
 * Una sola fila alimenta tres vistas —lista, matriz de Eisenhower y
 * Kanban— sin duplicar información. No existe columna «cuadrante»: se
 * deriva de `isUrgent` e `isImportant` en la consulta, de modo que no
 * puede desincronizarse de las banderas que la originan.
 */
export const tasks = pgTable('tasks', {
  id: pk(),
  userId: userRef(),
  title: text('title').notNull(),
  description: text('description'),
  status: taskStatus('status').notNull().default('todo'),
  isUrgent: boolean('is_urgent').notNull().default(false),
  isImportant: boolean('is_important').notNull().default(false),
  /**
   * UTC, siempre. La pertenencia al «día de hoy» se resuelve con
   * `AT TIME ZONE 'America/Bogota'`; comparar contra `current_date`
   * desplaza al día siguiente toda tarea posterior a las 19:00 locales.
   */
  dueDate: timestamp('due_date', { withTimezone: true }),
  /**
   * Orden dentro de la columna Kanban. `numeric` y no `integer`: permite
   * insertar entre dos vecinos calculando el punto medio, sin reescribir
   * el resto de la columna en cada arrastre.
   */
  boardOrder: numeric('board_order', { precision: 20, scale: 10 }).notNull().default('0'),
  category: text('category'),
  tags: jsonb('tags').$type<string[]>().notNull().default([]),
  /** Vínculo con el evento espejo en Google Calendar (§8.2). */
  calendarEventId: text('calendar_event_id'),
  completedAt: timestamp('completed_at', { withTimezone: true }),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [
  index('tasks_user_status_idx').on(t.userId, t.status),
  index('tasks_user_due_idx').on(t.userId, t.dueDate),
  index('tasks_user_quadrant_idx').on(t.userId, t.isUrgent, t.isImportant),
  index('tasks_board_idx').on(t.userId, t.status, t.boardOrder),
  uniqueIndex('tasks_calendar_event_key').on(t.calendarEventId),
]);
