import { bigint, index, integer, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';
import { fileStatus } from './enums';
import { userRef } from './identity';
import { createdAt, pk, updatedAt } from './_shared';

/**
 * Archivos (ARQUITECTURA.md §6.1).
 *
 * La fila nace `pending` y sólo pasa a `ready` cuando `commit` confirma,
 * mediante un HEAD contra el almacén, que el objeto existe y su tamaño
 * coincide con el declarado. Una carga abandonada deja una fila `pending`
 * que el barrido horario elimina — nunca un registro que promete un
 * archivo inexistente.
 */
export const files = pgTable('files', {
  id: pk(),
  userId: userRef(),
  /** Lo decide el servidor: `u/{userId}/{yyyy}/{mm}/{fileId}{ext}`. */
  objectKey: text('object_key').notNull(),
  /** Metadato, jamás componente de ruta. */
  originalName: text('original_name').notNull(),
  mimeType: text('mime_type').notNull(),
  sizeBytes: bigint('size_bytes', { mode: 'bigint' }).notNull(),
  status: fileStatus('status').notNull().default('pending'),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [
  uniqueIndex('files_object_key_key').on(t.objectKey),
  index('files_user_created_idx').on(t.userId, t.createdAt),
  index('files_status_idx').on(t.status, t.createdAt),
]);

/**
 * Enlaces públicos (§6.2).
 *
 * `tokenHash` es el SHA-256 de 32 bytes aleatorios: alta entropía, hash
 * rápido. `passwordHash` es argon2id porque ahí sí hay un secreto humano.
 * Cada credencial recibe el tratamiento que corresponde a su entropía.
 */
export const sharedLinks = pgTable('shared_links', {
  id: pk(),
  userId: userRef(),
  fileId: uuid('file_id').notNull().references(() => files.id, { onDelete: 'cascade' }),
  tokenHash: text('token_hash').notNull(),
  passwordHash: text('password_hash'),
  expiresAt: timestamp('expires_at', { withTimezone: true }),
  maxDownloads: integer('max_downloads'),
  downloadCount: integer('download_count').notNull().default(0),
  revokedAt: timestamp('revoked_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [
  uniqueIndex('shared_links_token_hash_key').on(t.tokenHash),
  index('shared_links_file_idx').on(t.fileId),
  index('shared_links_user_idx').on(t.userId),
]);

/**
 * Rastro de accesos (§6.4).
 *
 * Cumple dos funciones: auditoría, y desduplicación del contador de
 * descargas. Los navegadores emiten peticiones por rangos y reintentan;
 * contar peticiones revocaría enlaces legítimos. `countedAsDownload`
 * distingue el acceso que sí consumió cupo.
 */
export const shareAccessLog = pgTable('share_access_log', {
  id: pk(),
  sharedLinkId: uuid('shared_link_id').notNull().references(() => sharedLinks.id, { onDelete: 'cascade' }),
  ipHash: text('ip_hash'),
  userAgentHash: text('user_agent_hash'),
  /** `granted` | `denied_password` | `denied_expired` | `denied_exhausted` */
  outcome: text('outcome').notNull(),
  countedAsDownload: integer('counted_as_download').notNull().default(0),
  createdAt: createdAt(),
}, (t) => [
  index('share_access_link_time_idx').on(t.sharedLinkId, t.createdAt),
  index('share_access_dedup_idx').on(t.sharedLinkId, t.ipHash, t.userAgentHash, t.createdAt),
]);
