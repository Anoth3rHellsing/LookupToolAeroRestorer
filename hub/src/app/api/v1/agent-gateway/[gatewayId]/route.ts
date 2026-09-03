import { and, eq } from 'drizzle-orm';
import { NextResponse } from 'next/server';
import { dbTcp } from '@/db/client';
import { agentGateways, dashboardAnnouncements } from '@/db/schema';
import { clientIp, hashIdentifier, verifyToken } from '@/lib/crypto';
import { publishEvent } from '@/lib/events';
import { checkGate, recordAttempt } from '@/lib/gateway/rateLimit';
import {
  BODY_MAX_BYTES,
  announcementPayloadSchema,
  metadataWithinLimit,
} from '@/lib/gateway/schema';

/**
 * Pasarela de ingesta para agentes autónomos (ARQUITECTURA.md §11).
 *
 * Requiere conexión TCP (bus de eventos), de modo que no puede correr en
 * el runtime `edge`.
 */
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

interface Params {
  params: Promise<{ gatewayId: string }>;
}

export async function POST(request: Request, { params }: Params) {
  const { gatewayId } = await params;
  const ip = hashIdentifier(clientIp(request.headers));

  // ── 1. Tope de tamaño ANTES de leer el cuerpo ──────────────────────
  // Leer primero y medir después permitiría agotar la memoria del
  // contenedor con una única petición.
  const declaredLength = Number(request.headers.get('content-length') ?? '0');
  if (declaredLength > BODY_MAX_BYTES) {
    return NextResponse.json(
      { error: 'payload_too_large', maxBytes: BODY_MAX_BYTES },
      { status: 413 },
    );
  }

  // ── 2. Existencia de la pasarela ───────────────────────────────────
  const [gateway] = await dbTcp()
    .select()
    .from(agentGateways)
    .where(and(eq(agentGateways.id, gatewayId), eq(agentGateways.enabled, true)))
    .limit(1);

  // Respuesta y coste indistinguibles de una credencial incorrecta: el
  // atacante no debe poder enumerar identificadores válidos.
  if (!gateway) {
    await recordAttempt(null, ip, false, 'unknown_gateway');
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  // ── 3. Bloqueo por fallos y limitación de frecuencia ───────────────
  const gate = await checkGate(gateway.id, ip);
  if (!gate.allowed) {
    return NextResponse.json(
      { error: gate.reason },
      { status: 429, headers: { 'Retry-After': String(gate.retryAfterSeconds ?? 900) } },
    );
  }

  // ── 4. Autenticación ───────────────────────────────────────────────
  // SHA-256 en tiempo constante sobre un token de 256 bits. NO bcrypt:
  // 200-300 ms de CPU por petición no autenticada sería una denegación
  // de servicio por diseño (§11.2).
  const auth = request.headers.get('authorization') ?? '';
  const presented = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';

  if (!presented || !verifyToken(presented, gateway.tokenHash)) {
    await recordAttempt(gateway.id, ip, false, 'bad_token');
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  // ── 5. Validación del esquema ──────────────────────────────────────
  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    await recordAttempt(gateway.id, ip, false, 'malformed_json');
    return NextResponse.json({ error: 'malformed_json' }, { status: 400 });
  }

  const parsed = announcementPayloadSchema.safeParse(raw);
  if (!parsed.success) {
    await recordAttempt(gateway.id, ip, false, 'schema_violation');
    return NextResponse.json(
      { error: 'unprocessable_entity', issues: parsed.error.issues },
      { status: 422 },
    );
  }

  const payload = parsed.data;
  if (!metadataWithinLimit(payload.metadata)) {
    return NextResponse.json({ error: 'metadata_too_large' }, { status: 422 });
  }

  // ── 6. Idempotencia ────────────────────────────────────────────────
  // Los agentes autónomos reintentan ante timeout. Sin esto, el
  // Dashboard se llenaría de informes duplicados.
  const idempotencyKey = request.headers.get('idempotency-key');

  if (idempotencyKey) {
    const [existing] = await dbTcp()
      .select({ id: dashboardAnnouncements.id, createdAt: dashboardAnnouncements.createdAt })
      .from(dashboardAnnouncements)
      .where(
        and(
          eq(dashboardAnnouncements.gatewayId, gateway.id),
          eq(dashboardAnnouncements.idempotencyKey, idempotencyKey),
        ),
      )
      .limit(1);

    if (existing) {
      await recordAttempt(gateway.id, ip, true, 'idempotent_replay');
      return NextResponse.json(
        { id: existing.id, createdAt: existing.createdAt, replayed: true },
        { status: 200 },
      );
    }
  }

  // ── 7. Persistencia ────────────────────────────────────────────────
  // El contenido se almacena TAL CUAL, como texto plano, y se escapa al
  // renderizar. Nunca `dangerouslySetInnerHTML`: sanear al escribir
  // corrompe el dato y deja la puerta abierta a la codificación que se
  // olvidó contemplar.
  const expiresAt = payload.expiresInHours
    ? new Date(Date.now() + payload.expiresInHours * 3_600_000)
    : null;

  const [row] = await dbTcp()
    .insert(dashboardAnnouncements)
    .values({
      userId: gateway.userId,
      gatewayId: gateway.id,
      category: payload.category,
      title: payload.title,
      content: payload.content,
      importance: payload.importance,
      metadata: payload.metadata,
      expiresAt,
      idempotencyKey,
    })
    .returning({ id: dashboardAnnouncements.id, createdAt: dashboardAnnouncements.createdAt });

  await dbTcp()
    .update(agentGateways)
    .set({ lastUsedAt: new Date() })
    .where(eq(agentGateways.id, gateway.id));

  await recordAttempt(gateway.id, ip, true);

  // ── 8. Difusión en tiempo real ─────────────────────────────────────
  await publishEvent(gateway.userId, 'announcement', {
    announcementId: row!.id,
    category: payload.category,
    importance: payload.importance,
    title: payload.title,
  });

  return NextResponse.json({ id: row!.id, createdAt: row!.createdAt, replayed: false }, { status: 201 });
}

/**
 * Un GET aquí NO sirve el formulario web.
 *
 * La v1 proponía que un mismo endpoint decidiera su comportamiento según
 * si accedía «un navegador» —negociación por User-Agent o Accept, frágil
 * y fácil de confundir—. La modalidad interactiva vive en su propia ruta
 * (`/agent-submit/{gatewayId}`), y aquí se limita a señalarla.
 */
export function GET() {
  return NextResponse.json(
    { error: 'method_not_allowed', hint: 'La modalidad interactiva está en /agent-submit/{gatewayId}' },
    { status: 405, headers: { Allow: 'POST' } },
  );
}
