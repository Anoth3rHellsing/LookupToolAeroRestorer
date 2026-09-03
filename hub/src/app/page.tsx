import { IndicadorAntiguedad } from '@/components/IndicadorAntiguedad';

/**
 * Tablero principal (ARQUITECTURA.md §12.1).
 *
 * Grilla responsiva de tres zonas. En móvil se apilan en el orden en que
 * aparecen aquí, que es el orden de importancia: operativa del día,
 * boletín de inteligencia, resumen financiero.
 *
 * Los datos son de muestra: la Fase 1 los sustituye por consultas
 * reales. La estructura, los puntos de corte y el tratamiento de la
 * obsolescencia sí son definitivos.
 */
export default function Dashboard() {
  return (
    <div className="mx-auto w-full max-w-7xl px-4 py-6">
      <CintaIndicadores />

      <div className="mt-6 grid grid-cols-1 gap-4 lg:grid-cols-12">
        <section className="lg:col-span-3">
          <Tarjeta titulo="Foco del día">
            <p className="text-sm" style={{ color: 'var(--texto-tenue)' }}>
              Tareas del cuadrante urgente e importante, próximos eventos y hábitos del día.
            </p>
          </Tarjeta>
        </section>

        <section className="lg:col-span-6">
          <Tarjeta titulo="Boletín de inteligencia">
            <p className="text-sm" style={{ color: 'var(--texto-tenue)' }}>
              Último informe depositado por el agente externo, seguido de las noticias económicas.
            </p>
          </Tarjeta>
        </section>

        <section className="lg:col-span-3">
          <Tarjeta titulo="Resumen financiero">
            <p className="text-sm" style={{ color: 'var(--texto-tenue)' }}>
              Estado de la tarjeta principal y último entrenamiento registrado.
            </p>
          </Tarjeta>
        </section>
      </div>
    </div>
  );
}

/**
 * Cinta de indicadores.
 *
 * Cada dato lleva SU ANTIGÜEDAD. Es la diferencia entre informar y
 * mentir: un valor viejo etiquetado como viejo sigue siendo información;
 * un valor viejo presentado como actual es el peor modo de fallo del
 * sistema (§13.2).
 */
function CintaIndicadores() {
  const ahora = Date.now();
  const indicadores = [
    { etiqueta: 'TRM', valor: '$4.185,20', variacion: '+0,42 %', instante: new Date(ahora - 3 * 3600_000), umbralMin: 36 * 60 },
    { etiqueta: 'XAU/USD', valor: '$2.415,80', variacion: '−0,18 %', instante: new Date(ahora - 22 * 60_000), umbralMin: 180 },
    { etiqueta: 'Patrimonio', valor: '$48.320.400', variacion: null, instante: new Date(ahora), umbralMin: 1440 },
    { etiqueta: 'Racha', valor: '18 días', variacion: null, instante: new Date(ahora), umbralMin: 1440 },
  ];

  return (
    <div className="tabla-desplazable">
      <div className="flex min-w-max gap-3 lg:grid lg:min-w-0 lg:grid-cols-4">
        {indicadores.map((i) => (
          <div
            key={i.etiqueta}
            className="min-w-[9rem] rounded-xl border p-3"
            style={{ borderColor: 'var(--borde)', background: 'var(--superficie)' }}
          >
            <div className="flex items-baseline justify-between gap-2">
              <span className="text-xs uppercase tracking-wide" style={{ color: 'var(--texto-tenue)' }}>
                {i.etiqueta}
              </span>
              <IndicadorAntiguedad instante={i.instante} umbralMinutos={i.umbralMin} />
            </div>
            <p className="mt-1 text-lg font-semibold tabular-nums">{i.valor}</p>
            {i.variacion && (
              <p className="text-xs tabular-nums" style={{ color: 'var(--texto-tenue)' }}>
                {i.variacion}
              </p>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

function Tarjeta({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <div
      className="rounded-xl border p-4"
      style={{ borderColor: 'var(--borde)', background: 'var(--superficie)' }}
    >
      <h2 className="mb-2 text-sm font-semibold">{titulo}</h2>
      {children}
    </div>
  );
}
