import { trmJob } from './jobs/trm';
import { runJob, type Job } from './scheduler';

/**
 * Punto de entrada del despliegue `worker` (Reserved VM).
 *
 * Un único proceso residente en lugar de seis despliegues programados:
 * arranca una sola vez, mantiene viva la conexión TCP a PostgreSQL para
 * `LISTEN/NOTIFY` y resulta más barato (ARQUITECTURA.md §2).
 *
 * El planificador comprueba cada minuto qué corresponde ejecutar. No usa
 * cron externo para que la lógica de cadencia sea código versionado y
 * probable, no configuración dispersa por la consola del proveedor.
 */

const JOBS: Job[] = [
  trmJob,
  // Fase 3: xauJob, newsIngestJob, newsDigestJob, calendarSyncJob,
  //         linksSweepJob, jobsWatchdogJob.
];

const TICK_MS = 60_000;

async function tick(): Promise<void> {
  const now = new Date();
  const due = JOBS.filter((j) => j.due(now));
  // Secuencial y no en paralelo: el contenedor es pequeño y estos
  // trabajos son de espera de red, no de cómputo. Solaparlos sólo
  // aumentaría el pico de memoria sin ganar nada apreciable.
  for (const job of due) await runJob(job);
}

async function main(): Promise<void> {
  console.info(`[worker] Iniciado con ${JOBS.length} trabajo(s) registrado(s).`);

  let running = true;
  const stop = (signal: string) => {
    console.info(`[worker] ${signal} recibido; cerrando tras el ciclo en curso.`);
    running = false;
  };
  process.on('SIGTERM', () => stop('SIGTERM'));
  process.on('SIGINT', () => stop('SIGINT'));

  while (running) {
    try {
      await tick();
    } catch (err) {
      // El planificador nunca muere por un fallo de un ciclo.
      console.error('[worker] fallo en el ciclo:', err);
    }
    await new Promise((r) => setTimeout(r, TICK_MS));
  }

  console.info('[worker] Detenido limpiamente.');
  process.exit(0);
}

void main();
