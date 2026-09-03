import { index, jsonb, pgTable, text, timestamp, uniqueIndex } from 'drizzle-orm/pg-core';
import { bookmarkState } from './enums';
import { userRef } from './identity';
import { createdAt, pk, updatedAt } from './_shared';

/**
 * Repositorio de lectura posterior.
 *
 * `urlCanonical` y su hash comparten el criterio de normalización de las
 * noticias (§7.3): sin él, la misma página guardada desde un enlace con
 * parámetros de campaña entraría dos veces.
 *
 * La columna `search_vector` (tsvector generado, con índice GIN) se añade
 * en la migración `0001_search_vectors.sql`: Drizzle no la modela de forma
 * nativa, y una columna generada por PostgreSQL es preferible a mantener
 * el índice desde la aplicación.
 */
export const bookmarks = pgTable('bookmarks', {
  id: pk(),
  userId: userRef(),
  url: text('url').notNull(),
  urlCanonical: text('url_canonical').notNull(),
  urlHash: text('url_hash').notNull(),
  title: text('title'),
  description: text('description'),
  imageUrl: text('image_url'),
  siteName: text('site_name'),
  state: bookmarkState('state').notNull().default('unread'),
  tags: jsonb('tags').$type<string[]>().notNull().default([]),
  readAt: timestamp('read_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [
  uniqueIndex('bookmarks_user_url_hash_key').on(t.userId, t.urlHash),
  index('bookmarks_user_state_idx').on(t.userId, t.state, t.createdAt),
]);
