import { boolean, date, index, jsonb, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';
import { newsCategory } from './enums';
import { createdAt, pk, updatedAt } from './_shared';

export const newsSources = pgTable('news_sources', {
  id: pk(),
  name: text('name').notNull(),
  feedUrl: text('feed_url').notNull(),
  siteUrl: text('site_url'),
  category: newsCategory('category').notNull(),
  enabled: boolean('enabled').notNull().default(true),
  lastFetchedAt: timestamp('last_fetched_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [uniqueIndex('news_sources_feed_url_key').on(t.feedUrl)]);

/**
 * Artículos agregados (ARQUITECTURA.md §7.3).
 *
 * Se almacena EXCLUSIVAMENTE titular, extracto, autor, fecha y enlace de
 * origen; nunca el cuerpo íntegro. El sistema es un agregador que remite
 * al medio, no un espejo de su contenido.
 *
 * DESDUPLICACIÓN EN DOS NIVELES, corrigiendo la v1:
 *
 *   1. `urlHash` — SHA-256 sobre la URL CANÓNICA, no la cruda. El hash
 *      sobre la URL tal cual falla en cuanto un medio añade parámetros de
 *      campaña: la misma nota entra dos veces.
 *   2. `(sourceId, titleNormalized, publishedOn)` — atrapa la
 *      republicación con URL nueva, que el hash por sí solo deja pasar.
 */
export const newsArticles = pgTable('news_articles', {
  id: pk(),
  sourceId: uuid('source_id').notNull().references(() => newsSources.id, { onDelete: 'cascade' }),
  title: text('title').notNull(),
  titleNormalized: text('title_normalized').notNull(),
  summary: text('summary'),
  author: text('author'),
  url: text('url').notNull(),
  urlCanonical: text('url_canonical').notNull(),
  urlHash: text('url_hash').notNull(),
  publishedAt: timestamp('published_at', { withTimezone: true }).notNull(),
  publishedOn: date('published_on', { mode: 'string' }).notNull(),
  createdAt: createdAt(),
}, (t) => [
  uniqueIndex('news_articles_url_hash_key').on(t.urlHash),
  uniqueIndex('news_articles_title_dedup_key').on(t.sourceId, t.titleNormalized, t.publishedOn),
  index('news_articles_published_idx').on(t.publishedAt),
]);

/**
 * Resumen ejecutivo matutino generado por Claude (§7.4).
 *
 * `sourceArticleIds` conserva de qué titulares salió cada resumen: sin
 * esa trazabilidad, un resumen erróneo no puede auditarse contra su
 * origen.
 */
export const newsDigests = pgTable('news_digests', {
  id: pk(),
  digestDate: date('digest_date', { mode: 'string' }).notNull(),
  content: text('content').notNull(),
  sourceArticleIds: jsonb('source_article_ids').$type<string[]>().notNull().default([]),
  model: text('model').notNull(),
  createdAt: createdAt(),
}, (t) => [uniqueIndex('news_digests_date_key').on(t.digestDate)]);
