import { index, integer, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';
import { userRef } from './identity';
import { createdAt, money, pk, updatedAt } from './_shared';

export const workouts = pgTable('workouts', {
  id: pk(),
  userId: userRef(),
  performedAt: timestamp('performed_at', { withTimezone: true }).notNull(),
  title: text('title'),
  notes: text('notes'),
  durationMinutes: integer('duration_minutes'),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [index('workouts_user_performed_idx').on(t.userId, t.performedAt)]);

/**
 * `exerciseSlug` es la clave de comparación histórica: normaliza
 * «Press banca», «press de banca» y «Press Banca» a un mismo movimiento.
 * Sin ella, los récords personales se fragmentan por la ortografía.
 */
export const workoutExercises = pgTable('workout_exercises', {
  id: pk(),
  workoutId: uuid('workout_id').notNull().references(() => workouts.id, { onDelete: 'cascade' }),
  exerciseName: text('exercise_name').notNull(),
  exerciseSlug: text('exercise_slug').notNull(),
  position: integer('position').notNull().default(0),
  createdAt: createdAt(),
}, (t) => [index('workout_exercises_workout_idx').on(t.workoutId, t.position)]);

export const workoutSets = pgTable('workout_sets', {
  id: pk(),
  exerciseId: uuid('exercise_id').notNull().references(() => workoutExercises.id, { onDelete: 'cascade' }),
  setNumber: integer('set_number').notNull(),
  weightKg: money('weight_kg').notNull(),
  reps: integer('reps').notNull(),
  /** Esfuerzo percibido, escala 1–10 en pasos de 0,5. */
  rpe: money('rpe'),
  /**
   * 1RM proyectado por la ecuación de Epley, persistido en el momento del
   * registro. Se guarda en lugar de recalcularse para que un cambio
   * futuro de fórmula no reescriba el histórico de récords.
   */
  estimated1rm: money('estimated_1rm'),
  createdAt: createdAt(),
}, (t) => [uniqueIndex('workout_sets_exercise_number_key').on(t.exerciseId, t.setNumber)]);

/**
 * Récords personales por movimiento. Se mantiene como tabla propia —y no
 * como bandera `is_pr` sobre la serie— para que consultar «mi mejor press
 * banca» sea una lectura por índice y no un barrido del histórico.
 */
export const exerciseRecords = pgTable('exercise_records', {
  id: pk(),
  userId: userRef(),
  exerciseSlug: text('exercise_slug').notNull(),
  best1rm: money('best_1rm').notNull(),
  bestWeightKg: money('best_weight_kg').notNull(),
  achievedAt: timestamp('achieved_at', { withTimezone: true }).notNull(),
  setId: uuid('set_id').references(() => workoutSets.id, { onDelete: 'set null' }),
  updatedAt: updatedAt(),
}, (t) => [uniqueIndex('exercise_records_user_slug_key').on(t.userId, t.exerciseSlug)]);
