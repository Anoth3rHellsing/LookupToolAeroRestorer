import { sql } from 'drizzle-orm';
import { dbTcp } from '../db/client';
import { events } from '../db/schema';

/**
 * Bus de eventos (ARQUITECTURA.md §2.1).
 *
 * `NOTIFY` es efímero: si nadie escucha, el mensaje se pierde. Por eso
 * el productor escribe en la tabla `events` y un disparador emite la
 * notificación. La tabla es el registro DURABLE que permite al consumidor
 * SSE recuperar por cursor lo ocurrido durante una desconexión — que es
 * lo que hace correcto al sistema cuando Neon cierra una conexión ociosa.
 */

export type EventChannel = 'announcement' | 'market' | 'news' | 'task' | 'habit';

export interface HubEvent {
  id: number;
  channel: EventChannel;
  payload: Record<string, unknown>;
  createdAt: Date;
}

export async function publishEvent(
  userId: string,
  channel: EventChannel,
  payload: Record<string, unknown>,
): Promise<void> {
  // El disparador `events_notify` emite el pg_notify; no se invoca aquí
  // para que ninguna ruta de escritura pueda olvidarlo.
  await dbTcp().insert(events).values({ userId, channel, payload });
}

/** Recupera lo ocurrido desde un cursor. Es la red de seguridad del SSE. */
export async function eventsSince(userId: string, sinceId: number, limit = 100): Promise<HubEvent[]> {
  const rows = await dbTcp()
    .select()
    .from(events)
    .where(sql`${events.userId} = ${userId} AND ${events.id} > ${sinceId}`)
    .orderBy(events.id)
    .limit(limit);

  return rows.map((r) => ({
    id: r.id,
    channel: r.channel as EventChannel,
    payload: r.payload,
    createdAt: r.createdAt,
  }));
}

export async function latestEventId(userId: string): Promise<number> {
  const [row] = await dbTcp()
    .select({ id: sql<number>`coalesce(max(${events.id}), 0)` })
    .from(events)
    .where(sql`${events.userId} = ${userId}`);
  return row?.id ?? 0;
}
