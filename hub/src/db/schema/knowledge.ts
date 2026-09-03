import { index, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';
import { noteLinkKind } from './enums';
import { userRef } from './identity';
import { createdAt, pk, updatedAt } from './_shared';

export const notes = pgTable('notes', {
  id: pk(),
  userId: userRef(),
  title: text('title').notNull(),
  body: text('body').notNull().default(''),
  /**
   * Título normalizado (minúsculas, sin acentos ni espacios redundantes).
   * Es la clave por la que se resuelve `[[Enlace]]`: sin ella, «Cálculo»
   * y «calculo» serían dos nodos distintos del grafo.
   */
  slug: text('slug').notNull(),
  archivedAt: timestamp('archived_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [
  uniqueIndex('notes_user_slug_key').on(t.userId, t.slug),
  index('notes_user_updated_idx').on(t.userId, t.updatedAt),
]);

/**
 * Aristas del grafo topológico.
 *
 * Se materializan al guardar la nota, analizando `[[...]]` y `@...`. Un
 * enlace a una nota que aún no existe se conserva con `targetId` nulo y
 * `targetSlug` poblado: es un nodo fantasma, que el grafo dibuja en
 * trazo tenue y que se resuelve solo en cuanto la nota se cree.
 */
export const noteLinks = pgTable('note_links', {
  id: pk(),
  userId: userRef(),
  sourceNoteId: uuid('source_note_id').notNull().references(() => notes.id, { onDelete: 'cascade' }),
  kind: noteLinkKind('kind').notNull(),
  targetId: uuid('target_id'),
  targetSlug: text('target_slug').notNull(),
  createdAt: createdAt(),
}, (t) => [
  uniqueIndex('note_links_edge_key').on(t.sourceNoteId, t.kind, t.targetSlug),
  index('note_links_target_idx').on(t.userId, t.kind, t.targetSlug),
]);
