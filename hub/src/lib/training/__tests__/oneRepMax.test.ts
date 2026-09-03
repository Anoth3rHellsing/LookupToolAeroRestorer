import { describe, expect, it } from 'vitest';
import { brzycki, checkPersonalRecord, epley, exerciseSlug, isReliableEstimate, setVolume } from '../oneRepMax';

describe('epley', () => {
  it('aplica la ecuación del documento original', () => {
    // 100 kg x 5 rep -> 100 · (1 + 5/30) = 116,667
    expect(epley(100, 5).toDecimalPlaces(4).toString()).toBe('116.6667');
  });

  it('con una sola repetición devuelve la carga, no la infla', () => {
    // La fórmula literal daría 103,33 kg para un levantamiento que YA es
    // el máximo: sería un récord inventado.
    expect(epley(100, 1).toString()).toBe('100');
  });

  it('crece con las repeticiones', () => {
    expect(epley(100, 8).gt(epley(100, 5))).toBe(true);
  });

  it('rechaza entradas imposibles', () => {
    expect(() => epley(100, 0)).toThrow(RangeError);
    expect(() => epley(-10, 5)).toThrow(RangeError);
  });
});

describe('brzycki', () => {
  it('coincide con Epley en la carga de una repetición', () => {
    expect(brzycki(100, 1).toString()).toBe('100');
  });

  it('coincide EXACTAMENTE con Epley en diez repeticiones', () => {
    // Punto de corte de ambas curvas: (1 + r/30)(37 - r) = 36 -> r = 10.
    // 100 * (1 + 10/30) = 133,33   y   100 * 36/27 = 133,33
    expect(brzycki(100, 10).toDecimalPlaces(4).toString())
      .toBe(epley(100, 10).toDecimalPlaces(4).toString());
  });

  it('estima por DEBAJO de Epley por debajo del punto de corte', () => {
    expect(brzycki(100, 5).lt(epley(100, 5))).toBe(true);
  });

  it('estima por ENCIMA de Epley por encima del punto de corte', () => {
    // La divergencia es justamente lo que marca el umbral de fiabilidad.
    expect(brzycki(100, 12).gt(epley(100, 12))).toBe(true);
  });

  it('no está definida a partir de 37 repeticiones', () => {
    expect(() => brzycki(100, 37)).toThrow(RangeError);
  });
});

describe('isReliableEstimate', () => {
  it('marca como orientativa la estimación por encima de diez repeticiones', () => {
    expect(isReliableEstimate(5)).toBe(true);
    expect(isReliableEstimate(10)).toBe(true);
    expect(isReliableEstimate(15)).toBe(false);
  });
});

describe('checkPersonalRecord', () => {
  it('el primer registro de un movimiento siempre es récord', () => {
    const r = checkPersonalRecord(100, 5, null);
    expect(r.isRecord).toBe(true);
    expect(r.previousBest).toBeNull();
  });

  it('reconoce la mejora y la cuantifica', () => {
    const r = checkPersonalRecord(105, 5, '116.6667');
    expect(r.isRecord).toBe(true);
    expect(r.improvement!.gt(0)).toBe(true);
  });

  it('no declara récord al igualar la marca anterior', () => {
    const r = checkPersonalRecord(100, 5, '116.6667');
    expect(r.isRecord).toBe(false);
    expect(r.improvement).toBeNull();
  });

  it('reconoce que menos carga a más repeticiones puede ser récord', () => {
    // 95 x 10 = 126,7 supera a 100 x 5 = 116,7.
    expect(checkPersonalRecord(95, 10, '116.6667').isRecord).toBe(true);
  });
});

describe('exerciseSlug', () => {
  it('unifica variantes ortográficas del mismo movimiento', () => {
    const esperado = 'press-de-banca';
    expect(exerciseSlug('Press de Banca')).toBe(esperado);
    expect(exerciseSlug('press de banca')).toBe(esperado);
    expect(exerciseSlug('  PRESS  DE  BANCA  ')).toBe(esperado);
  });

  it('elimina los acentos', () => {
    expect(exerciseSlug('Elevación lateral')).toBe('elevacion-lateral');
  });

  it('no fusiona movimientos distintos', () => {
    expect(exerciseSlug('Press militar')).not.toBe(exerciseSlug('Press de banca'));
  });
});

describe('setVolume', () => {
  it('calcula el tonelaje de la serie', () => {
    expect(setVolume(100, 5).toString()).toBe('500');
  });
});
