import { sql } from 'drizzle-orm';
import { dbTcp } from '../../db/client';
import { gatewayAttempts } from '../../db/schema';

/**
 * Limitación de frecuencia y bloqueo por fallos (ARQUITECTURA.md §11.3).
 *
 * Vive en la base de datos y no en memoria de proceso por una razón
 * concreta: el contenedor se reinicia, y un atacante no debe recuperar
 * sus intentos fallidos con sólo esperar a que Replit recicle la
 * instancia.
 */

export const MAX_REQUESTS_PER_HOUR = 60;
export const MAX_CONSECUTIVE_FAILURES = 5;
export const LOCKOUT_MINUTES = 15;

export interface GateDecision {
  allowed: boolean;
  reason?: 'rate_limited' | 'locked_out';
  retryAfterSeconds?: number;
}

export async function recordAttempt(
  gatewayId: string | null,
  ipHash: string | null,
  succeeded: boolean,
  reason?: string,
): Promise<void> {
  await dbTcp().insert(gatewayAttempts).values({ gatewayId, ipHash, succeeded, reason });
}

export async function checkGate(gatewayId: string, ipHash: string | null): Promise<GateDecision> {
  const [counts] = await dbTcp()
    .select({
      lastHour: sql<number>`count(*) filter (where created_at > now() - interval '1 hour')`,
      recentFailures: sql<number>`count(*) filter (
        where succeeded = false and created_at > now() - interval '${sql.raw(String(LOCKOUT_MINUTES))} minutes'
      )`,
      lastSuccessAt: sql<Date | null>`max(created_at) filter (where succeeded = true)`,
    })
    .from(gatewayAttempts)
    .where(sql`gateway_id = ${gatewayId} or (ip_hash is not null and ip_hash = ${ipHash})`);

  if (!counts) return { allowed: true };

  if (Number(counts.recentFailures) >= MAX_CONSECUTIVE_FAILURES) {
    return { allowed: false, reason: 'locked_out', retryAfterSeconds: LOCKOUT_MINUTES * 60 };
  }
  if (Number(counts.lastHour) >= MAX_REQUESTS_PER_HOUR) {
    return { allowed: false, reason: 'rate_limited', retryAfterSeconds: 3600 };
  }
  return { allowed: true };
}
