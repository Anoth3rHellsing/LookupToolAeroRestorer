import Decimal from 'decimal.js';

// 28 dígitos significativos: holgura sobrada para encadenar potencias y
// divisiones en el cálculo de anualidades sin arrastrar error.
Decimal.set({ precision: 28, rounding: Decimal.ROUND_HALF_UP });

export type CurrencyCode = 'COP' | 'USD' | 'EUR';

/**
 * Unidades menores por divisa.
 *
 * El peso colombiano se opera en unidades enteras: presentar «$4.185,37»
 * en un saldo en pesos es ruido, no precisión. El dólar y el euro sí
 * tienen céntimos.
 */
const MINOR_UNITS: Record<CurrencyCode, number> = { COP: 0, USD: 2, EUR: 2 };

export function minorUnits(currency: CurrencyCode): number {
  return MINOR_UNITS[currency];
}

export function dec(value: Decimal.Value): Decimal {
  return new Decimal(value);
}

/** Redondea a la unidad menor de la divisa, media al alza. */
export function roundTo(value: Decimal.Value, currency: CurrencyCode): Decimal {
  return new Decimal(value).toDecimalPlaces(MINOR_UNITS[currency], Decimal.ROUND_HALF_UP);
}

/**
 * Serializa para `numeric(20,4)`. La base de datos guarda cuatro
 * decimales con independencia de la divisa: el redondeo a la unidad menor
 * es una decisión de presentación y de cuadre de cuotas, no de
 * almacenamiento.
 */
export function toDbNumeric(value: Decimal.Value): string {
  return new Decimal(value).toFixed(4);
}

export function fromDbNumeric(value: string | null | undefined): Decimal {
  return new Decimal(value ?? '0');
}

export function formatMoney(
  value: Decimal.Value,
  currency: CurrencyCode,
  locale = 'es-CO',
): string {
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency,
    minimumFractionDigits: MINOR_UNITS[currency],
    maximumFractionDigits: MINOR_UNITS[currency],
  }).format(new Decimal(value).toNumber());
}

export { Decimal };
