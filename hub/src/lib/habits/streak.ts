export type HabitState = 'completed' | 'skipped' | 'failed';

export interface HabitLogEntry {
  /** `YYYY-MM-DD` en la zona del usuario. */
  logDate: string;
  state: HabitState;
}

export interface StreakResult {
  current: number;
  longest: number;
  /** Días congelados por «saltar», que no cuentan pero tampoco rompen. */
  frozenDays: number;
}

function shiftDay(isoDate: string, delta: number): string {
  const d = new Date(`${isoDate}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
}

const previousDay = (isoDate: string): string => shiftDay(isoDate, -1);
const nextDay = (isoDate: string): string => shiftDay(isoDate, 1);

/**
 * Motor de rachas con flexibilidad operativa (ARQUITECTURA.md, hábitos).
 *
 * Lo que distingue este motor de un contador binario: el estado
 * `skipped` CONGELA la racha acumulada sin restablecerla a cero. Sólo
 * `failed` —o la ausencia de registro en un día pasado— la rompe.
 *
 * La ausencia de registro en el día EN CURSO no rompe nada: la jornada
 * todavía no ha terminado. Tratarla como fallo castigaría al usuario por
 * consultar su panel por la mañana.
 */
export function computeStreak(logs: HabitLogEntry[], todayIso: string): StreakResult {
  const byDate = new Map(logs.map((l) => [l.logDate, l.state]));

  let current = 0;
  let frozen = 0;
  let cursor = todayIso;

  // El día en curso sólo suma si ya está registrado; su ausencia no rompe.
  if (!byDate.has(cursor)) cursor = previousDay(cursor);

  while (byDate.has(cursor)) {
    const state = byDate.get(cursor)!;
    if (state === 'failed') break;
    if (state === 'completed') current += 1;
    else frozen += 1;
    cursor = previousDay(cursor);
  }

  // La racha más larga se calcula sobre la serie completa en orden.
  const ordered = [...logs].sort((a, b) => a.logDate.localeCompare(b.logDate));
  let longest = 0;
  let run = 0;
  let expected: string | null = null;

  for (const entry of ordered) {
    // Un hueco en el calendario rompe la serie igual que un fallo.
    if (expected !== null && entry.logDate !== expected) run = 0;
    if (entry.state === 'failed') run = 0;
    else if (entry.state === 'completed') run += 1;
    // `skipped` no incrementa ni rompe.
    longest = Math.max(longest, run);
    expected = nextDay(entry.logDate);
  }

  return { current, longest: Math.max(longest, current), frozenDays: frozen };
}
