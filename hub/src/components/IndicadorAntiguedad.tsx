import { ageInMinutes } from '@/lib/time';

/**
 * Marca de obsolescencia (ARQUITECTURA.md §13.2).
 *
 * Nunca se muestra un hueco ni un cero cuando falla la ingesta: se
 * muestra el último valor bueno CON SU ANTIGÜEDAD, y se destaca en
 * ámbar cuando supera el umbral del dominio.
 *
 * Un dato viejo etiquetado como viejo es información. Un cero es una
 * mentira, y es lo que ocurriría si la interfaz no distinguiera entre
 * «no hay dato» y «el dato vale cero».
 */
export function IndicadorAntiguedad({
  instante,
  umbralMinutos,
}: {
  instante: Date | null;
  umbralMinutos: number;
}) {
  const minutos = ageInMinutes(instante);
  const obsoleto = minutos > umbralMinutos;

  return (
    <span
      className="shrink-0 text-[10px] tabular-nums"
      style={{ color: obsoleto ? 'var(--alerta)' : 'var(--texto-tenue)' }}
      title={instante ? instante.toISOString() : 'Sin dato'}
    >
      {obsoleto && '⚠ '}
      {describirAntiguedad(minutos)}
    </span>
  );
}

function describirAntiguedad(minutos: number): string {
  if (!Number.isFinite(minutos)) return 'sin dato';
  if (minutos < 2) return 'ahora';
  if (minutos < 60) return `hace ${Math.round(minutos)} min`;
  const horas = minutos / 60;
  if (horas < 24) return `hace ${Math.round(horas)} h`;
  return `hace ${Math.round(horas / 24)} d`;
}
