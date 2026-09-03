import type { Decimal } from '../money';

/**
 * Contrato común de proveedores externos (ARQUITECTURA.md §7.1).
 *
 * Todo origen externo implementa la misma interfaz, de modo que el fallo
 * de un proveedor sea un cambio de implementación y no una reescritura.
 * La v1 preveía respaldo para la TRM pero no para el oro; esta interfaz
 * elimina esa asimetría por construcción.
 */
export interface Quote {
  value: Decimal;
  asOf: Date;
  source: string;
  /** La TRM rige un rango de vigencia, no un día suelto (§7.2). */
  validFrom?: string;
  validTo?: string;
  bid?: Decimal;
  ask?: Decimal;
}

export interface QuoteProvider {
  readonly name: string;
  fetch(signal?: AbortSignal): Promise<Quote>;
}

/**
 * Recorre los proveedores en orden de preferencia y se detiene en el
 * primer éxito.
 *
 * Si TODOS fallan lanza un error agregado, y quien llama NO escribe nada:
 * el último valor bueno permanece en la tabla y la interfaz lo muestra
 * con su antigüedad real. Escribir un cero o un hueco sería peor que no
 * escribir nada.
 */
export async function fetchWithFallback(
  providers: QuoteProvider[],
  timeoutMs = 10_000,
): Promise<Quote> {
  const failures: string[] = [];

  for (const provider of providers) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const quote = await provider.fetch(controller.signal);
      if (!quote.value.isFinite() || quote.value.lte(0)) {
        throw new Error('cotización no positiva o no finita');
      }
      return quote;
    } catch (err) {
      failures.push(`${provider.name}: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      clearTimeout(timer);
    }
  }

  throw new AggregateError(
    failures.map((f) => new Error(f)),
    `Todos los proveedores fallaron: ${failures.join(' | ')}`,
  );
}
