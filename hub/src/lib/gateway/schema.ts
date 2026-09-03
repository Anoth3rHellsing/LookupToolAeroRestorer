import { z } from 'zod';

/**
 * Contrato del payload de la pasarela (ARQUITECTURA.md §11.4).
 *
 * Los límites se declaran aquí Y en el motor (restricciones
 * `announcements_title_length` y `announcements_content_length`): la
 * validación de la aplicación da un mensaje de error útil, la de la base
 * de datos garantiza la invariante frente a cualquier otro escritor.
 */
export const announcementPayloadSchema = z
  .object({
    category: z.enum(['market_analysis', 'daily_report', 'alert', 'reminder', 'note']),
    title: z.string().min(1).max(200),
    content: z.string().min(1).max(20_000),
    importance: z.enum(['low', 'normal', 'high', 'critical']).default('normal'),
    metadata: z.record(z.string(), z.unknown()).default({}),
    expiresInHours: z.number().int().min(1).max(720).optional(),
  })
  .strict(); // Un campo desconocido es un error del agente, no algo a ignorar.

export type AnnouncementPayload = z.infer<typeof announcementPayloadSchema>;

/** Tope de metadatos: 4 KiB serializados. */
export const METADATA_MAX_BYTES = 4096;
/** Tope de cuerpo: se rechaza por `Content-Length` antes de leer nada. */
export const BODY_MAX_BYTES = 64 * 1024;

export function metadataWithinLimit(metadata: Record<string, unknown>): boolean {
  return Buffer.byteLength(JSON.stringify(metadata), 'utf8') <= METADATA_MAX_BYTES;
}
