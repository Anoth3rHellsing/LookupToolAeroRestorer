import { formatInTimeZone, toZonedTime } from 'date-fns-tz';

/**
 * Fronteras de día (ARQUITECTURA.md §8.1).
 *
 * Todo instante se persiste en UTC; la noción de «día» se deriva siempre
 * en la zona del usuario. Comparar `due_date::date` contra `current_date`
 * desplaza al día siguiente toda tarea posterior a las 19:00 en Bogotá.
 * Comprobado sobre PostgreSQL: `2026-09-04 01:30 UTC` es el 3 de
 * septiembre en Bogotá, no el 4.
 */

export const DEFAULT_TIMEZONE = 'America/Bogota';

/** Fecha civil `YYYY-MM-DD` del instante en la zona indicada. */
export function localDate(instant: Date, timeZone = DEFAULT_TIMEZONE): string {
  return formatInTimeZone(instant, timeZone, 'yyyy-MM-dd');
}

export function today(timeZone = DEFAULT_TIMEZONE): string {
  return localDate(new Date(), timeZone);
}

/** Clave `YYYY-MM` de presupuesto, coherente con `budgets_month_key_format`. */
export function monthKey(instant: Date, timeZone = DEFAULT_TIMEZONE): string {
  return formatInTimeZone(instant, timeZone, 'yyyy-MM');
}

/** ¿Cae el instante en el día civil local indicado? */
export function isOnLocalDate(instant: Date, isoDate: string, timeZone = DEFAULT_TIMEZONE): boolean {
  return localDate(instant, timeZone) === isoDate;
}

/** Hora local en 0–23; la usa el planificador para sus ventanas. */
export function localHour(instant: Date, timeZone = DEFAULT_TIMEZONE): number {
  return Number(formatInTimeZone(instant, timeZone, 'H'));
}

export function zoned(instant: Date, timeZone = DEFAULT_TIMEZONE): Date {
  return toZonedTime(instant, timeZone);
}

/** Antigüedad en minutos. Alimenta el vigía de obsolescencia (§13.2). */
export function ageInMinutes(instant: Date | null | undefined, now = new Date()): number {
  if (!instant) return Number.POSITIVE_INFINITY;
  return (now.getTime() - instant.getTime()) / 60000;
}
