import { describe, expect, it } from 'vitest';
import { computeStreak, type HabitLogEntry } from '../streak';

const log = (logDate: string, state: HabitLogEntry['state']): HabitLogEntry => ({ logDate, state });

describe('computeStreak', () => {
  it('cuenta los días consecutivos completados', () => {
    const r = computeStreak(
      [log('2026-09-01', 'completed'), log('2026-09-02', 'completed'), log('2026-09-03', 'completed')],
      '2026-09-03',
    );
    expect(r.current).toBe(3);
  });

  it('EL PUNTO DEL DISEÑO: «saltar» congela la racha, no la restablece', () => {
    const r = computeStreak(
      [
        log('2026-09-01', 'completed'),
        log('2026-09-02', 'completed'),
        log('2026-09-03', 'skipped'), // enfermedad, viaje, fuerza mayor
        log('2026-09-04', 'completed'),
      ],
      '2026-09-04',
    );
    expect(r.current).toBe(3); // los tres completados siguen contando
    expect(r.frozenDays).toBe(1);
  });

  it('un fallo sí rompe la racha', () => {
    const r = computeStreak(
      [
        log('2026-09-01', 'completed'),
        log('2026-09-02', 'failed'),
        log('2026-09-03', 'completed'),
      ],
      '2026-09-03',
    );
    expect(r.current).toBe(1);
  });

  it('no castiga por consultar el panel antes de registrar el día', () => {
    // Sin registro de hoy, la racha de ayer se mantiene: la jornada aún
    // no ha terminado.
    const r = computeStreak(
      [log('2026-09-01', 'completed'), log('2026-09-02', 'completed')],
      '2026-09-03',
    );
    expect(r.current).toBe(2);
  });

  it('un hueco en el calendario rompe la racha', () => {
    const r = computeStreak(
      [log('2026-09-01', 'completed'), log('2026-09-05', 'completed')],
      '2026-09-05',
    );
    expect(r.current).toBe(1);
  });

  it('recuerda la racha más larga aunque la actual se haya roto', () => {
    const r = computeStreak(
      [
        log('2026-09-01', 'completed'),
        log('2026-09-02', 'completed'),
        log('2026-09-03', 'completed'),
        log('2026-09-04', 'failed'),
        log('2026-09-05', 'completed'),
      ],
      '2026-09-05',
    );
    expect(r.current).toBe(1);
    expect(r.longest).toBe(3);
  });

  it('devuelve ceros sin registros', () => {
    expect(computeStreak([], '2026-09-03')).toEqual({ current: 0, longest: 0, frozenDays: 0 });
  });

  it('cruza el fin de mes', () => {
    const r = computeStreak(
      [log('2026-08-30', 'completed'), log('2026-08-31', 'completed'), log('2026-09-01', 'completed')],
      '2026-09-01',
    );
    expect(r.current).toBe(3);
  });
});
