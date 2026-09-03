import { Decimal, dec } from '../money';

/**
 * Máximo teórico de una repetición (ARQUITECTURA.md §9 / entrenamiento).
 *
 * Ecuación de Epley, que es la que especificaba el documento original:
 *
 *     1RM = Peso · (1 + Repeticiones / 30)
 *
 * Es correcta, con una salvedad que la v1 no recogía: toda estimación de
 * 1RM se degrada al aumentar las repeticiones, y las distintas fórmulas
 * dejan de coincidir.
 *
 * Epley y Brzycki se cortan EXACTAMENTE en 10 repeticiones. Igualando
 * ambas expresiones:
 *
 *     (1 + r/30)·(37 − r) = 36   →   r² − 7r − 30 = 0   →   r = 10
 *
 * Por debajo de diez, Brzycki estima por debajo de Epley; por encima, al
 * revés. Ese punto de corte es lo que da fundamento objetivo al umbral
 * RELIABLE_REP_CEILING: mientras las dos fórmulas concuerdan, la
 * estimación es defendible; en cuanto divergen, es orientativa y la
 * interfaz debe decirlo en lugar de presentar un número con falsa
 * autoridad.
 */

export function epley(weightKg: Decimal.Value, reps: number): Decimal {
  if (reps < 1) throw new RangeError('Las repeticiones deben ser al menos una.');
  const w = dec(weightKg);
  if (w.lt(0)) throw new RangeError('La carga no puede ser negativa.');
  // Una única repetición ya ES el máximo: la fórmula lo inflaría un 3,3 %.
  if (reps === 1) return w;
  return w.times(dec(1).plus(dec(reps).div(30)));
}

/** Brzycki: 1RM = Peso · 36 / (37 − Repeticiones). Más estable en series cortas. */
export function brzycki(weightKg: Decimal.Value, reps: number): Decimal {
  if (reps < 1) throw new RangeError('Las repeticiones deben ser al menos una.');
  if (reps >= 37) throw new RangeError('Brzycki no está definida a partir de 37 repeticiones.');
  const w = dec(weightKg);
  if (reps === 1) return w;
  return w.times(36).div(37 - reps);
}

/** Punto de corte entre Epley y Brzycki; véase la nota de cabecera. */
export const RELIABLE_REP_CEILING = 10;

export function isReliableEstimate(reps: number): boolean {
  return reps >= 1 && reps <= RELIABLE_REP_CEILING;
}

export interface PersonalRecordCheck {
  isRecord: boolean;
  estimated1rm: Decimal;
  previousBest: Decimal | null;
  improvement: Decimal | null;
}

/**
 * Decide si una serie constituye récord personal.
 *
 * Se compara contra el mejor 1RM histórico del MISMO movimiento,
 * identificado por su `slug` normalizado: sin esa normalización, «Press
 * banca» y «press de banca» mantendrían récords separados.
 */
export function checkPersonalRecord(
  weightKg: Decimal.Value,
  reps: number,
  previousBest: Decimal.Value | null,
): PersonalRecordCheck {
  const estimated = epley(weightKg, reps);
  const prev = previousBest === null ? null : dec(previousBest);

  if (prev === null) {
    return { isRecord: true, estimated1rm: estimated, previousBest: null, improvement: null };
  }

  const isRecord = estimated.gt(prev);
  return {
    isRecord,
    estimated1rm: estimated,
    previousBest: prev,
    improvement: isRecord ? estimated.minus(prev) : null,
  };
}

/** Tonelaje de una serie: carga × repeticiones. */
export function setVolume(weightKg: Decimal.Value, reps: number): Decimal {
  return dec(weightKg).times(reps);
}

/** Normaliza el nombre del ejercicio a su `slug` de comparación histórica. */
export function exerciseSlug(name: string): string {
  return name
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}
