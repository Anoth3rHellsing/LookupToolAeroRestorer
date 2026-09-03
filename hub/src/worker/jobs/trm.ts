import { sql } from 'drizzle-orm';
import { dbTcp } from '../../db/client';
import { marketRates } from '../../db/schema';
import { toDbNumeric } from '../../lib/money';
import { TRM_PROVIDERS } from '../../lib/providers/trm';
import { fetchWithFallback } from '../../lib/providers/types';
import { publishEvent } from '../../lib/events';
import { atLocalHour, type Job } from '../scheduler';

/**
 * Ingesta de la TRM (ARQUITECTURA.md §7.2).
 *
 * Cadencia a las 18:00 y 19:30 COT más reintento a las 06:00: la TRM del
 * día siguiente se publica oficialmente al final de la tarde, y el
 * segundo pase cubre una publicación tardía sin esperar al día siguiente.
 */
export const trmJob: Job = {
  name: 'trm.sync',
  due: atLocalHour(6, 18, 19),

  async run() {
    const quote = await fetchWithFallback(TRM_PROVIDERS);

    if (!quote.validFrom || !quote.validTo) {
      throw new Error('El proveedor no informó el rango de vigencia de la TRM.');
    }

    // `onConflictDoUpdate` sobre (pair, valid_from): reejecutar el
    // trabajo el mismo día es idempotente, y una corrección posterior
    // del valor oficial sí se refleja.
    const result = await dbTcp()
      .insert(marketRates)
      .values({
        pair: 'USDCOP',
        value: toDbNumeric(quote.value),
        validFrom: quote.validFrom,
        validTo: quote.validTo,
        source: quote.source,
        fetchedAt: new Date(),
      })
      .onConflictDoUpdate({
        target: [marketRates.pair, marketRates.validFrom],
        set: {
          value: toDbNumeric(quote.value),
          validTo: quote.validTo,
          source: quote.source,
          fetchedAt: new Date(),
        },
      })
      .returning({ id: marketRates.id });

    const [owner] = await dbTcp().execute<{ id: string }>(
      sql`select id from users order by created_at limit 1`,
    ).then((r) => (r as unknown as { rows: { id: string }[] }).rows ?? []);

    if (owner) {
      await publishEvent(owner.id, 'market', {
        pair: 'USDCOP',
        value: quote.value.toString(),
        validFrom: quote.validFrom,
        source: quote.source,
      });
    }

    return {
      rowsAffected: result.length,
      // Deja constancia de si se sirvió el origen oficial o el respaldo.
      detail: { source: quote.source, validFrom: quote.validFrom, validTo: quote.validTo },
    };
  },
};
