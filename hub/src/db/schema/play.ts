import { index, integer, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';
import { chatRole } from './enums';
import { userRef } from './identity';
import { createdAt, pk, updatedAt } from './_shared';

/**
 * Hoja de personaje (ARQUITECTURA.md §10.3).
 *
 * Estas columnas componen el bloque `system` CONGELADO. Todo lo que aquí
 * vive es prefijo estable y por tanto cacheable; nada volátil puede
 * entrar, o el caché de prompts se invalidaría en cada turno.
 *
 * NOTA SOBRE `temperature`: la hoja de personaje de la v1 incluía
 * `"temperature": 0.85`. Los parámetros de muestreo (`temperature`,
 * `top_p`, `top_k`) fueron RETIRADOS en esta generación de modelos y
 * devuelven error 400. El control equivalente es `output_config.effort`,
 * que es lo que persiste `effort`.
 */
export const characters = pgTable('characters', {
  id: pk(),
  userId: userRef(),
  slug: text('slug').notNull(),
  name: text('name').notNull(),
  /** Identidad, tono, trasfondo y restricciones diegéticas. */
  personaPrompt: text('persona_prompt').notNull(),
  staticLore: text('static_lore').notNull().default(''),
  avatarUrl: text('avatar_url'),
  effort: text('effort').notNull().default('low'),
  maxTokensPerResponse: integer('max_tokens_per_response').notNull().default(1024),
  archivedAt: timestamp('archived_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [uniqueIndex('characters_user_slug_key').on(t.userId, t.slug)]);

export const conversations = pgTable('conversations', {
  id: pk(),
  userId: userRef(),
  characterId: uuid('character_id').notNull().references(() => characters.id, { onDelete: 'cascade' }),
  title: text('title'),
  lastMessageAt: timestamp('last_message_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [index('conversations_user_recent_idx').on(t.userId, t.lastMessageAt)]);

export const chatMessages = pgTable('chat_messages', {
  id: pk(),
  conversationId: uuid('conversation_id').notNull().references(() => conversations.id, { onDelete: 'cascade' }),
  role: chatRole('role').notNull(),
  content: text('content').notNull(),
  /** Índice monótono dentro de la conversación: ordena y pagina sin ambigüedad. */
  position: integer('position').notNull(),
  /**
   * Telemetría de caché. Si `cacheReadTokens` es cero de forma sostenida,
   * hay un invalidador silencioso en el prefijo y el módulo NO está
   * terminado, por muy bien que responda (§10.3).
   */
  inputTokens: integer('input_tokens'),
  outputTokens: integer('output_tokens'),
  cacheReadTokens: integer('cache_read_tokens'),
  cacheWriteTokens: integer('cache_write_tokens'),
  model: text('model'),
  createdAt: createdAt(),
}, (t) => [uniqueIndex('chat_messages_conv_position_key').on(t.conversationId, t.position)]);

/**
 * Memoria compactada de la conversación.
 *
 * Se PERSISTE, no se guarda en memoria de proceso: el contenedor es
 * efímero y una conversación no puede perder su hilo argumental porque
 * Replit reciclara la instancia.
 *
 * `coversUpToPosition` marca hasta qué mensaje resume, de modo que la
 * compactación sea incremental y no reprocese lo ya resumido.
 *
 * En la llamada a la API este texto viaja como mensaje `{role:"system"}`
 * DENTRO del array `messages` — nunca en el campo `system` de nivel
 * superior, que debe permanecer byte a byte idéntico para que el caché
 * de prefijo siga sirviendo.
 */
export const conversationMemories = pgTable('conversation_memories', {
  id: pk(),
  conversationId: uuid('conversation_id').notNull().references(() => conversations.id, { onDelete: 'cascade' }),
  summary: text('summary').notNull(),
  coversUpToPosition: integer('covers_up_to_position').notNull(),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [uniqueIndex('conversation_memories_conv_key').on(t.conversationId)]);
