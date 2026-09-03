import { eventsSince, latestEventId } from '@/lib/events';
import { pgPool } from '@/db/client';

/**
 * Canal SSE hacia el navegador (ARQUITECTURA.md §2.1).
 *
 * Dos mecanismos, y el segundo es el que lo hace correcto:
 *
 *   1. `LISTEN hub_events` sobre una conexión TCP dedicada — latencia
 *      inmediata.
 *   2. Recuperación por cursor sobre la tabla `events` — Neon cierra
 *      conexiones ociosas y suspende el endpoint, de modo que el canal
 *      SE CAERÁ. Al reconectar, el cliente envía `Last-Event-ID` y se le
 *      entrega todo lo ocurrido durante el hueco.
 *
 * Sin el punto 2, cada suspensión de Neon perdería anuncios en silencio.
 */
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const KEEPALIVE_MS = 20_000;

export async function GET(request: Request) {
  // TODO(fase 1): resolver el usuario desde la cookie de sesión.
  const userId = request.headers.get('x-user-id');
  if (!userId) return new Response('unauthorized', { status: 401 });

  const url = new URL(request.url);
  const lastEventId = Number(
    request.headers.get('last-event-id') ?? url.searchParams.get('lastEventId') ?? '0',
  );

  const encoder = new TextEncoder();
  let cursor = Number.isFinite(lastEventId) && lastEventId > 0 ? lastEventId : await latestEventId(userId);

  const stream = new ReadableStream({
    async start(controller) {
      const send = (data: string) => controller.enqueue(encoder.encode(data));

      const flush = async () => {
        const pending = await eventsSince(userId, cursor);
        for (const e of pending) {
          cursor = e.id;
          send(`id: ${e.id}\nevent: ${e.channel}\ndata: ${JSON.stringify(e.payload)}\n\n`);
        }
      };

      // Entrega inmediata de lo perdido durante la desconexión anterior.
      await flush();

      const client = await pgPool().connect();
      let keepalive: NodeJS.Timeout | undefined;
      let closed = false;

      const cleanup = () => {
        if (closed) return;
        closed = true;
        if (keepalive) clearInterval(keepalive);
        client.removeAllListeners('notification');
        client.query('UNLISTEN hub_events').catch(() => {});
        client.release();
        try { controller.close(); } catch { /* ya cerrado */ }
      };

      try {
        await client.query('LISTEN hub_events');

        client.on('notification', (msg) => {
          // El payload de NOTIFY sólo trae el identificador: PostgreSQL
          // limita la notificación a 8000 bytes y un anuncio de 20 000
          // caracteres la desbordaría. La fila se lee por su id.
          try {
            const parsed = JSON.parse(msg.payload ?? '{}') as { userId?: string };
            if (parsed.userId !== userId) return;
          } catch { return; }
          void flush().catch(() => cleanup());
        });

        // Comentario periódico: atraviesa proxies que cortan conexiones
        // ociosas y detecta al cliente que ya no está.
        keepalive = setInterval(() => {
          try { send(': keepalive\n\n'); } catch { cleanup(); }
        }, KEEPALIVE_MS);

        request.signal.addEventListener('abort', cleanup);
      } catch (err) {
        console.error('[sse] fallo al establecer LISTEN:', err);
        cleanup();
      }
    },
  });

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      // Impide que un proxy intermedio bufferice el flujo y anule el
      // tiempo real por el que existe este endpoint.
      'X-Accel-Buffering': 'no',
    },
  });
}
