import { sql } from 'drizzle-orm';
import { bigint, boolean, index, jsonb, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';
import { createdAt, pk, updatedAt } from './_shared';

/**
 * Identidad (ARQUITECTURA.md §4).
 *
 * El producto es monousuario, pero el esquema es multiusuario: toda tabla
 * de negocio referencia `users.id` con borrado en cascada. Hoy cuesta una
 * columna y un índice; añadirla más tarde obligaría a reescribir cada
 * consulta del sistema.
 */
export const users = pgTable('users', {
  id: pk(),
  email: text('email').notNull(),
  /** argon2id — secreto humano de baja entropía, hash deliberadamente lento. */
  passwordHash: text('password_hash').notNull(),
  displayName: text('display_name').notNull(),
  /** Toda frontera de día del sistema se deriva de esta zona. */
  timezone: text('timezone').notNull().default('America/Bogota'),
  baseCurrency: text('base_currency').notNull().default('COP'),
  /** Cifrado con AES-256-GCM (§4.2). Nulo mientras el 2FA esté desactivado. */
  totpSecret: text('totp_secret'),
  storageQuotaBytes: bigint('storage_quota_bytes', { mode: 'bigint' })
    .notNull()
    .default(sql`21474836480`),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [uniqueIndex('users_email_key').on(t.email)]);

/** Referencia estándar al propietario. Todo dato de negocio la lleva. */
export const userRef = () =>
  uuid('user_id')
    .notNull()
    .references(() => users.id, { onDelete: 'cascade' });

/**
 * Sesiones. La cookie transporta un token opaco de 32 bytes; aquí sólo
 * vive su SHA-256, de modo que una filtración de la base de datos no
 * entrega sesiones utilizables.
 */
export const sessions = pgTable('sessions', {
  id: pk(),
  userId: userRef(),
  tokenHash: text('token_hash').notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  lastSeenAt: timestamp('last_seen_at', { withTimezone: true }).notNull().defaultNow(),
  ipHash: text('ip_hash'),
  userAgent: text('user_agent'),
  createdAt: createdAt(),
}, (t) => [
  uniqueIndex('sessions_token_hash_key').on(t.tokenHash),
  index('sessions_user_idx').on(t.userId),
  index('sessions_expires_idx').on(t.expiresAt),
]);

/**
 * Credenciales OAuth de terceros (hoy: Google Calendar).
 *
 * `refreshTokenEncrypted` guarda el formato versionado
 * `v1.<nonce>.<ciphertext>.<authTag>` descrito en §4.2. El nonce es único
 * por operación de cifrado: reutilizarlo con la misma clave rompe GCM.
 */
export const oauthAccounts = pgTable('oauth_accounts', {
  id: pk(),
  userId: userRef(),
  provider: text('provider').notNull(),
  providerAccountId: text('provider_account_id').notNull(),
  refreshTokenEncrypted: text('refresh_token_encrypted').notNull(),
  scopes: jsonb('scopes').$type<string[]>().notNull().default([]),
  /** Cursor de sincronización incremental de Calendar (§8.2). */
  syncToken: text('sync_token'),
  syncedAt: timestamp('synced_at', { withTimezone: true }),
  revoked: boolean('revoked').notNull().default(false),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [
  uniqueIndex('oauth_provider_account_key').on(t.provider, t.providerAccountId),
  index('oauth_user_idx').on(t.userId),
]);
