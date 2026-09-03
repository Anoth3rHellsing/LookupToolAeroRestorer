import { boolean, index, jsonb, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';
import { announcementCategory, announcementImportance } from './enums';
import { userRef } from './identity';
import { createdAt, pk, updatedAt } from './_shared';

/**
 * Pasarela de ingesta para agentes (ARQUITECTURA.md §11).
 *
 * CORRECCIÓN DE SEGURIDAD respecto a la v1. Aquella verificaba una
 * contraseña con bcrypt de factor 12 en CADA petición: 200–300 ms de CPU
 * por intento, incluido el no autenticado. En un contenedor pequeño,
 * cualquiera que descubriese el `gatewayId` saturaría el núcleo. Era una
 * denegación de servicio por diseño.
 *
 * Aquí la credencial de máquina es un token de 32 bytes aleatorios, del
 * que se persiste sólo el SHA-256. Con 256 bits de entropía un hash lento
 * no aporta nada frente a fuerza bruta, y sí abre el vector de DoS.
 *
 * `formPasswordHash` sí es argon2id: es la contraseña que teclea una
 * persona en el formulario web, y ahí el hash lento es exactamente lo
 * correcto. Cada credencial recibe el tratamiento que merece su entropía.
 */
export const agentGateways = pgTable('agent_gateways', {
  id: pk(),
  userId: userRef(),
  name: text('name').notNull(),
  tokenHash: text('token_hash').notNull(),
  formPasswordHash: text('form_password_hash'),
  enabled: boolean('enabled').notNull().default(true),
  lastUsedAt: timestamp('last_used_at', { withTimezone: true }),
  rotatedAt: timestamp('rotated_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [
  uniqueIndex('agent_gateways_token_hash_key').on(t.tokenHash),
  index('agent_gateways_user_idx').on(t.userId),
]);

/**
 * Intentos contra la pasarela.
 *
 * Vive en la base de datos y no en memoria por una razón concreta: el
 * contenedor se reinicia, y un atacante no debe recuperar sus intentos
 * fallidos con sólo esperar a que Replit recicle la instancia.
 *
 * Sostiene a la vez el bloqueo por fallos (5 consecutivos → 15 min) y la
 * limitación de frecuencia (60/hora).
 */
export const gatewayAttempts = pgTable('gateway_attempts', {
  id: pk(),
  gatewayId: uuid('gateway_id').references(() => agentGateways.id, { onDelete: 'cascade' }),
  /** Primera entrada de X-Forwarded-For; tras el proxy de Replit, remoteAddress es siempre el proxy. */
  ipHash: text('ip_hash'),
  succeeded: boolean('succeeded').notNull(),
  reason: text('reason'),
  createdAt: createdAt(),
}, (t) => [
  index('gateway_attempts_gateway_time_idx').on(t.gatewayId, t.createdAt),
  index('gateway_attempts_ip_time_idx').on(t.ipHash, t.createdAt),
]);

/**
 * Informes depositados por agentes externos.
 *
 * `idempotencyKey` es indispensable, no un adorno: los agentes autónomos
 * reintentan ante timeout, y sin él el Dashboard se llena de informes
 * duplicados. El índice único hace que el reintento devuelva el registro
 * original en lugar de crear otro.
 */
export const dashboardAnnouncements = pgTable('dashboard_announcements', {
  id: pk(),
  userId: userRef(),
  gatewayId: uuid('gateway_id').references(() => agentGateways.id, { onDelete: 'set null' }),
  category: announcementCategory('category').notNull(),
  title: text('title').notNull(),
  content: text('content').notNull(),
  importance: announcementImportance('importance').notNull().default('normal'),
  metadata: jsonb('metadata').$type<Record<string, unknown>>().notNull().default({}),
  expiresAt: timestamp('expires_at', { withTimezone: true }),
  readAt: timestamp('read_at', { withTimezone: true }),
  idempotencyKey: text('idempotency_key'),
  createdAt: createdAt(),
}, (t) => [
  uniqueIndex('announcements_gateway_idempotency_key').on(t.gatewayId, t.idempotencyKey),
  index('announcements_user_recent_idx').on(t.userId, t.createdAt),
  index('announcements_expiry_idx').on(t.expiresAt),
]);
