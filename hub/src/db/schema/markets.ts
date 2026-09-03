import { date, index, pgTable, text, timestamp, uniqueIndex } from 'drizzle-orm/pg-core';
import { createdAt, money, pk } from './_shared';

/**
 * TRM (ARQUITECTURA.md §7.2).
 *
 * Precisión que la v1 pasaba por alto: la TRM es válida para un RANGO de
 * vigencia, no para un día suelto. El valor certificado un viernes rige
 * también sábado y domingo. Modelar `validFrom`/`validTo` en lugar de una
 * sola fecha es lo que permite responder correctamente «¿qué TRM aplicaba
 * el domingo?» sin inventar interpolaciones.
 *
 * Tabla global, sin `userId`: es un dato de mercado, no del usuario.
 */
export const marketRates = pgTable('market_rates', {
  id: pk(),
  pair: text('pair').notNull(),
  value: money('value').notNull(),
  validFrom: date('valid_from', { mode: 'string' }).notNull(),
  validTo: date('valid_to', { mode: 'string' }).notNull(),
  /** Proveedor efectivo: revela cuándo se sirvió el respaldo (§7.1). */
  source: text('source').notNull(),
  fetchedAt: timestamp('fetched_at', { withTimezone: true }).notNull().defaultNow(),
  createdAt: createdAt(),
}, (t) => [
  uniqueIndex('market_rates_pair_from_key').on(t.pair, t.validFrom),
  index('market_rates_pair_range_idx').on(t.pair, t.validFrom, t.validTo),
]);

/**
 * Materias primas al contado (XAU/USD).
 *
 * La v1 preveía respaldo para la TRM pero no para el oro; el contrato de
 * proveedores de §7.1 elimina esa asimetría y `source` la hace auditable.
 */
export const marketCommodities = pgTable('market_commodities', {
  id: pk(),
  symbol: text('symbol').notNull(),
  bid: money('bid'),
  ask: money('ask'),
  mid: money('mid').notNull(),
  source: text('source').notNull(),
  quotedAt: timestamp('quoted_at', { withTimezone: true }).notNull(),
  createdAt: createdAt(),
}, (t) => [
  index('market_commodities_symbol_time_idx').on(t.symbol, t.quotedAt),
]);
