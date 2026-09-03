import { describe, expect, it } from 'vitest';
import { dec } from '../../money';
import {
  addMonths,
  annualToMonthlyRate,
  buildAmortizationPlan,
  monthlyPayment,
  v1Understatement,
} from '../amortization';

describe('annualToMonthlyRate', () => {
  it('convierte la efectiva anual a efectiva mensual, no a la nominal', () => {
    // 24 % E.A. -> (1,24)^(1/12) - 1 = 1,8088 % mensual.
    const i = annualToMonthlyRate('0.24');
    expect(i.toDecimalPlaces(6).toString()).toBe('0.018088');
  });

  it('no es la división ingenua por doce', () => {
    // 0,24/12 = 2 % daría una tasa NOMINAL, que sobreestima el interés
    // mensual y por tanto la cuota. Son cosas distintas.
    const efectiva = annualToMonthlyRate('0.24');
    expect(efectiva.lt(dec('0.24').div(12))).toBe(true);
  });

  it('recompone la anual al capitalizar doce meses', () => {
    const i = annualToMonthlyRate('0.24');
    expect(i.plus(1).pow(12).minus(1).toDecimalPlaces(10).toString()).toBe('0.24');
  });

  it('devuelve cero para tasa cero', () => {
    expect(annualToMonthlyRate(0).isZero()).toBe(true);
  });
});

describe('monthlyPayment', () => {
  it('EL DEFECTO DE LA v1: con interés, la cuota es MAYOR que capital/plazo', () => {
    const principal = dec('1200000');
    const months = 12;
    const naive = principal.div(months); // fórmula de la v1: 100.000

    const real = monthlyPayment(principal, months, '0.02', 'COP');

    expect(naive.toString()).toBe('100000');
    expect(real.gt(naive)).toBe(true);
    // Al 2 % mensual la cuota real ronda los 113.500 pesos: la v1
    // ocultaba más de 13.000 pesos mensuales al usuario.
    expect(real.toNumber()).toBeGreaterThan(113000);
    expect(real.toNumber()).toBeLessThan(114000);
  });

  it('con interés cero sí coincide con la división simple', () => {
    const c = monthlyPayment('1200000', 12, 0, 'COP');
    expect(c.toString()).toBe('100000');
  });

  it('redondea a la unidad menor de la divisa', () => {
    expect(monthlyPayment('1000', 3, '0.01', 'COP').decimalPlaces()).toBe(0);
    expect(monthlyPayment('1000', 3, '0.01', 'USD').decimalPlaces()).toBeLessThanOrEqual(2);
  });

  it('rechaza entradas imposibles', () => {
    expect(() => monthlyPayment('1000', 0, '0.01', 'COP')).toThrow(RangeError);
    expect(() => monthlyPayment('0', 12, '0.01', 'COP')).toThrow(RangeError);
    expect(() => monthlyPayment('1000', 12, '-0.01', 'COP')).toThrow(RangeError);
  });
});

describe('buildAmortizationPlan', () => {
  const base = {
    principal: '1200000',
    months: 12,
    currency: 'COP' as const,
    firstDueOn: '2026-02-15',
  };

  it('la suma de los abonos a capital iguala EXACTAMENTE al capital', () => {
    const plan = buildAmortizationPlan({ ...base, monthlyRate: '0.02' });
    const suma = plan.items.reduce((a, it) => a.plus(it.principalPortion), dec(0));
    expect(suma.toString()).toBe('1200000');
  });

  it('el saldo final es exactamente cero', () => {
    const plan = buildAmortizationPlan({ ...base, monthlyRate: '0.02' });
    expect(plan.items.at(-1)!.remainingBalance.isZero()).toBe(true);
  });

  it('cada cuota cuadra: pago = interés + capital', () => {
    const plan = buildAmortizationPlan({ ...base, monthlyRate: '0.0215' });
    for (const it of plan.items) {
      expect(it.payment.equals(it.interestPortion.plus(it.principalPortion))).toBe(true);
    }
  });

  it('el total pagado es capital más intereses, sin residuo', () => {
    const plan = buildAmortizationPlan({ ...base, monthlyRate: '0.02' });
    expect(plan.totalPaid.equals(dec('1200000').plus(plan.totalInterest))).toBe(true);
  });

  it('el interés decrece y el abono a capital crece a lo largo del plan', () => {
    const plan = buildAmortizationPlan({ ...base, monthlyRate: '0.02' });
    for (let k = 1; k < plan.items.length - 1; k += 1) {
      expect(plan.items[k]!.interestPortion.lte(plan.items[k - 1]!.interestPortion)).toBe(true);
      expect(plan.items[k]!.principalPortion.gte(plan.items[k - 1]!.principalPortion)).toBe(true);
    }
  });

  it('con interés cero reproduce el comportamiento esperado de la v1', () => {
    const plan = buildAmortizationPlan({ ...base, monthlyRate: 0 });
    expect(plan.totalInterest.isZero()).toBe(true);
    expect(plan.totalPaid.toString()).toBe('1200000');
    for (const it of plan.items) expect(it.payment.toString()).toBe('100000');
  });

  it('el residuo de redondeo se absorbe en la última cuota', () => {
    // 1.000 pesos a 3 cuotas no divide exacto: 333,33...
    const plan = buildAmortizationPlan({
      principal: '1000', months: 3, monthlyRate: 0, currency: 'COP', firstDueOn: '2026-01-31',
    });
    const suma = plan.items.reduce((a, it) => a.plus(it.principalPortion), dec(0));
    expect(suma.toString()).toBe('1000');
    // Las dos primeras son iguales; la última difiere para cuadrar.
    expect(plan.items[0]!.payment.toString()).toBe(plan.items[1]!.payment.toString());
    expect(plan.items[2]!.payment.equals(plan.items[0]!.payment)).toBe(false);
  });

  it('rechaza una cuota que no cubra el interés del periodo', () => {
    // A tasas desorbitadas la cuota es interés puro: el abono a capital
    // se anula y el saldo nunca bajaría. Es una condición imposible de
    // sostener, no un caso que deba redondearse en silencio.
    expect(() =>
      buildAmortizationPlan({
        principal: '1000000', months: 36, monthlyRate: '5', currency: 'COP', firstDueOn: '2026-01-01',
      }),
    ).toThrow(RangeError);
  });

  it('no produce falsos positivos en el rango real del mercado colombiano', () => {
    // La tasa de usura ronda el 2,5–3 % mensual. Ninguna combinación
    // plausible de tasa y plazo debe activar la guarda anterior.
    for (const tasa of ['0.015', '0.02', '0.025', '0.03', '0.035']) {
      for (const n of [1, 6, 12, 24, 36]) {
        const plan = buildAmortizationPlan({
          principal: '3000000', months: n, monthlyRate: tasa, currency: 'COP', firstDueOn: '2026-01-15',
        });
        const suma = plan.items.reduce((a, it) => a.plus(it.principalPortion), dec(0));
        expect(suma.toString(), `tasa ${tasa} plazo ${n}`).toBe('3000000');
      }
    }
  });

  it('cuadra también en divisa con céntimos', () => {
    const plan = buildAmortizationPlan({
      principal: '999.99', months: 7, monthlyRate: '0.0175', currency: 'USD', firstDueOn: '2026-03-31',
    });
    const suma = plan.items.reduce((a, it) => a.plus(it.principalPortion), dec(0));
    expect(suma.toString()).toBe('999.99');
    expect(plan.items.at(-1)!.remainingBalance.isZero()).toBe(true);
  });

  it('cuadra para todo plazo admitido por el esquema (1 a 36)', () => {
    for (let n = 1; n <= 36; n += 1) {
      const plan = buildAmortizationPlan({
        principal: '2500000', months: n, monthlyRate: '0.0215', currency: 'COP', firstDueOn: '2026-01-15',
      });
      const suma = plan.items.reduce((a, it) => a.plus(it.principalPortion), dec(0));
      expect(suma.toString(), `plazo ${n}`).toBe('2500000');
      expect(plan.items.at(-1)!.remainingBalance.isZero(), `plazo ${n}`).toBe(true);
    }
  });
});

describe('addMonths', () => {
  it('conserva el fin de mes en lugar de desbordar', () => {
    // Una compra diferida el 31 de enero vence el 28 de febrero.
    expect(addMonths('2026-01-31', 1)).toBe('2026-02-28');
    expect(addMonths('2026-01-31', 3)).toBe('2026-04-30');
  });

  it('respeta los años bisiestos', () => {
    expect(addMonths('2028-01-31', 1)).toBe('2028-02-29');
  });

  it('cruza el cambio de año', () => {
    expect(addMonths('2026-11-15', 3)).toBe('2027-02-15');
    expect(addMonths('2026-12-01', 12)).toBe('2027-12-01');
  });
});

describe('v1Understatement', () => {
  it('cuantifica lo que la fórmula original ocultaba al usuario', () => {
    const plan = buildAmortizationPlan({
      principal: '1200000', months: 12, monthlyRate: '0.02', currency: 'COP', firstDueOn: '2026-02-15',
    });
    const diferencia = v1Understatement(plan, '1200000', 12);
    expect(diferencia.gt(13000)).toBe(true);
  });
});
