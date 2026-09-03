import { Decimal, dec, minorUnits, roundTo, type CurrencyCode } from '../money';

/**
 * Amortización de compras diferidas (ARQUITECTURA.md §9.3).
 *
 * ─────────────────────────────────────────────────────────────────────
 * CORRECCIÓN CENTRAL respecto al documento original.
 *
 * La v1 especificaba:
 *
 *     Cuota = Monto Capital / Plazo de Cuotas
 *
 * Eso describe un diferimiento SIN intereses. En el mercado colombiano
 * las compras a cuotas devengan interés corriente casi siempre, de modo
 * que esa fórmula mostraría al usuario una deuda sistemáticamente
 * INFERIOR a la real — el peor error posible en un módulo financiero.
 *
 * La cuota fija de una anualidad vencida es:
 *
 *              i
 *     C = P · ───────────────
 *             1 − (1 + i)⁻ⁿ
 *
 * La v1 no estaba equivocada en el caso i = 0; estaba equivocada al
 * tratar ese caso particular como el general.
 * ─────────────────────────────────────────────────────────────────────
 */

export interface AmortizationInput {
  principal: Decimal.Value;
  months: number;
  /** Tasa mensual efectiva en tanto por uno (0,0215 = 2,15 % mensual). */
  monthlyRate: Decimal.Value;
  currency: CurrencyCode;
  /** Vencimiento de la primera cuota, `YYYY-MM-DD`. */
  firstDueOn: string;
}

export interface Installment {
  number: number;
  dueOn: string;
  payment: Decimal;
  interestPortion: Decimal;
  principalPortion: Decimal;
  remainingBalance: Decimal;
}

export interface AmortizationPlan {
  monthlyPayment: Decimal;
  totalInterest: Decimal;
  totalPaid: Decimal;
  items: Installment[];
}

/**
 * Convierte una tasa efectiva anual a su equivalente mensual efectiva:
 *
 *     i = (1 + i_EA)^(1/12) − 1
 *
 * No es `i_EA / 12`. Esa división da la tasa NOMINAL, que subestima el
 * coste real y es la confusión más común en este cálculo.
 */
export function annualToMonthlyRate(annualEffective: Decimal.Value): Decimal {
  const ea = dec(annualEffective);
  if (ea.isZero()) return dec(0);
  return ea.plus(1).pow(dec(1).div(12)).minus(1);
}

/** Cuota fija de la anualidad. Bifurca explícitamente en i = 0. */
export function monthlyPayment(
  principal: Decimal.Value,
  months: number,
  monthlyRate: Decimal.Value,
  currency: CurrencyCode,
): Decimal {
  const p = dec(principal);
  const i = dec(monthlyRate);

  if (months < 1) throw new RangeError('El plazo debe ser de al menos una cuota.');
  if (p.lte(0)) throw new RangeError('El capital debe ser positivo.');
  if (i.lt(0)) throw new RangeError('La tasa no puede ser negativa.');

  // Sin interés la expresión general es indeterminada (0/0).
  if (i.isZero()) return roundTo(p.div(months), currency);

  const factor = dec(1).minus(dec(1).plus(i).pow(-months));
  return roundTo(p.times(i).div(factor), currency);
}

/**
 * Tabla de amortización completa.
 *
 * El descuadre de redondeo se absorbe ÍNTEGRAMENTE en la última cuota,
 * de modo que la suma de los abonos a capital iguale exactamente al
 * capital y el saldo final sea cero. Un céntimo descuadrado a doce cuotas
 * destruye la confianza en todo el módulo contable.
 */
export function buildAmortizationPlan(input: AmortizationInput): AmortizationPlan {
  const { months, currency, firstDueOn } = input;
  const principal = dec(input.principal);
  const rate = dec(input.monthlyRate);
  const payment = monthlyPayment(principal, months, rate, currency);

  const items: Installment[] = [];
  let balance = principal;
  let accumulatedInterest = dec(0);

  for (let n = 1; n <= months; n += 1) {
    const isLast = n === months;
    let interest = roundTo(balance.times(rate), currency);
    let principalPortion: Decimal;
    let thisPayment: Decimal;

    if (isLast) {
      // La cuota final liquida el saldo exacto, sea cual sea el residuo
      // que hayan dejado los redondeos anteriores.
      principalPortion = balance;
      thisPayment = principalPortion.plus(interest);
    } else {
      thisPayment = payment;
      principalPortion = thisPayment.minus(interest);

      // Con plazos largos y tasas altas la cuota podría no cubrir ni el
      // interés, y el saldo crecería en lugar de amortizarse. Es una
      // condición imposible de sostener, no un caso a redondear.
      if (principalPortion.lte(0)) {
        throw new RangeError(
          'La cuota no cubre el interés del periodo: el saldo nunca se amortizaría.',
        );
      }
    }

    balance = balance.minus(principalPortion);
    accumulatedInterest = accumulatedInterest.plus(interest);

    items.push({
      number: n,
      dueOn: addMonths(firstDueOn, n - 1),
      payment: thisPayment,
      interestPortion: interest,
      principalPortion,
      remainingBalance: balance,
    });
  }

  const totalPaid = items.reduce((acc, it) => acc.plus(it.payment), dec(0));

  return {
    monthlyPayment: payment,
    totalInterest: accumulatedInterest,
    totalPaid,
    items,
  };
}

/**
 * Suma meses conservando el fin de mes.
 *
 * Una compra diferida el 31 de enero vence el 28 de febrero, no el 3 de
 * marzo. `Date` con día 31 en un mes de 30 desborda al siguiente, de modo
 * que se sujeta al último día real del mes destino.
 */
export function addMonths(isoDate: string, months: number): string {
  const [y, m, d] = isoDate.split('-').map(Number) as [number, number, number];
  const targetMonthIndex = m - 1 + months;
  const year = y + Math.floor(targetMonthIndex / 12);
  const month = ((targetMonthIndex % 12) + 12) % 12;
  const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const day = Math.min(d, lastDay);
  return `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

/** Cuánto subestimaría la fórmula de la v1. Sirve de aviso en la interfaz. */
export function v1Understatement(plan: AmortizationPlan, principal: Decimal.Value, months: number): Decimal {
  const naive = dec(principal).div(months);
  return plan.monthlyPayment.minus(naive);
}

export { minorUnits };
