import Anthropic from '@anthropic-ai/sdk';

/**
 * Integración con Claude (ARQUITECTURA.md §10).
 *
 * ─────────────────────────────────────────────────────────────────────
 * CORRECCIÓN MÁS COSTOSA respecto al documento original.
 *
 * La v1 inyectaba el bloque de «Memoria Reciente» DENTRO del campo
 * `system` en cada llamada. El caché de prompts funciona por
 * COINCIDENCIA DE PREFIJO: alterar un solo byte del prefijo invalida
 * todo lo que le sigue. Con esa estrategia, cada resumen nuevo obliga a
 * pagar íntegros la hoja de personaje y el lore, turno tras turno, para
 * siempre.
 *
 * Aquí el `system` queda CONGELADO y cacheado, y la memoria viaja como
 * mensaje `{role:'system'}` DENTRO del array `messages`. El prefijo
 * permanece intacto y el caché sirve en cada turno.
 * ─────────────────────────────────────────────────────────────────────
 */

export const DEFAULT_MODEL = process.env.ANTHROPIC_MODEL ?? 'claude-opus-5';
export const COMPACTION_MODEL = process.env.ANTHROPIC_COMPACTION_MODEL ?? 'claude-haiku-4-5';

/** Intercambios que permanecen literales antes de compactarse. */
export const RECENT_EXCHANGE_WINDOW = 12;

let singleton: Anthropic | null = null;

export function anthropic(): Anthropic {
  if (!singleton) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error('ANTHROPIC_API_KEY no está definida.');
    singleton = new Anthropic({ apiKey });
  }
  return singleton;
}

export interface CharacterSheet {
  name: string;
  personaPrompt: string;
  staticLore: string;
  effort: 'low' | 'medium' | 'high';
  maxTokensPerResponse: number;
}

export interface Exchange {
  role: 'user' | 'assistant';
  content: string;
}

export interface RoleplayContext {
  character: CharacterSheet;
  /** Últimos intercambios literales, en orden cronológico. */
  recent: Exchange[];
  /** Resumen compactado persistido, o nulo si la conversación es corta. */
  memory: string | null;
  userMessage: string;
}

/**
 * Construye el bloque `system` congelado.
 *
 * TODO lo que entra aquí debe ser estable entre turnos. Nada de marcas de
 * tiempo, contadores, ni JSON sin orden determinista: cualquiera de esas
 * cosas es un invalidador silencioso del caché.
 *
 * Se expone como función pura precisamente para poder AFIRMAR en una
 * prueba que dos turnos distintos producen bytes idénticos.
 */
export function buildSystemBlocks(character: CharacterSheet): Anthropic.TextBlockParam[] {
  const text = [
    character.personaPrompt.trim(),
    character.staticLore.trim() ? `\n\n## Contexto permanente\n\n${character.staticLore.trim()}` : '',
  ].join('');

  return [
    {
      type: 'text',
      text,
      // El punto de corte del caché. Todo lo anterior se reutiliza.
      cache_control: { type: 'ephemeral' },
    },
  ];
}

/**
 * Ensambla el array `messages`.
 *
 * La memoria se coloca como ÚLTIMA entrada, tras el mensaje del usuario.
 * Dos razones:
 *
 *   1. Un mensaje `system` intraconversacional debe seguir a un mensaje
 *      `user` y ser el último elemento o ir seguido de un turno del
 *      asistente. Esta posición cumple ambas condiciones.
 *   2. Al ir al final, no invalida el prefijo formado por el historial:
 *      recompactar la memoria no cuesta el caché de toda la conversación.
 *
 * Es además el canal correcto para instrucciones de operador, resistente
 * a inyección desde el contenido del propio diálogo.
 */
export function buildMessages(ctx: RoleplayContext): Anthropic.MessageParam[] {
  const messages: Anthropic.MessageParam[] = ctx.recent.map((e) => ({
    role: e.role,
    content: e.content,
  }));

  messages.push({ role: 'user', content: ctx.userMessage });

  if (ctx.memory?.trim()) {
    messages.push({
      role: 'system',
      content: `## Memoria de la conversación\n\n${ctx.memory.trim()}`,
    } as unknown as Anthropic.MessageParam);
  }

  return messages;
}

export function buildRoleplayRequest(ctx: RoleplayContext) {
  return {
    model: DEFAULT_MODEL,
    max_tokens: ctx.character.maxTokensPerResponse,
    system: buildSystemBlocks(ctx.character),
    messages: buildMessages(ctx),
    // Los parámetros de muestreo (`temperature`, `top_p`, `top_k`) fueron
    // retirados en esta generación y devuelven 400. La hoja de personaje
    // de la v1 fijaba `temperature: 0.85`; el control vigente es `effort`.
    thinking: { type: 'adaptive' as const },
    output_config: { effort: ctx.character.effort },
  };
}

/** Transmite la respuesta del personaje. El consumidor la reenvía por SSE. */
export function streamRoleplay(ctx: RoleplayContext) {
  return anthropic().messages.stream(buildRoleplayRequest(ctx) as Parameters<
    ReturnType<typeof anthropic>['messages']['stream']
  >[0]);
}

export interface UsageRecord {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
}

/**
 * Extrae la telemetría de caché.
 *
 * `cacheReadTokens` en cero de forma sostenida significa que hay un
 * invalidador silencioso en el prefijo. El módulo NO está terminado
 * mientras eso ocurra, por bien que responda.
 */
export function extractUsage(usage: Anthropic.Usage): UsageRecord {
  return {
    inputTokens: usage.input_tokens ?? 0,
    outputTokens: usage.output_tokens ?? 0,
    cacheReadTokens: usage.cache_read_input_tokens ?? 0,
    cacheWriteTokens: usage.cache_creation_input_tokens ?? 0,
  };
}

/**
 * Compacta los intercambios antiguos en un resumen persistible.
 *
 * Se usa el modelo más económico porque la tarea es extractiva, y el
 * resultado se guarda en `conversation_memories`: el contenedor es
 * efímero y una conversación no puede perder su hilo argumental porque
 * Replit reciclara la instancia.
 */
export async function compactMemory(
  previousMemory: string | null,
  exchanges: Exchange[],
): Promise<string> {
  const transcript = exchanges.map((e) => `${e.role === 'user' ? 'Usuario' : 'Personaje'}: ${e.content}`).join('\n\n');

  const response = await anthropic().messages.create({
    model: COMPACTION_MODEL,
    max_tokens: 1024,
    system:
      'Extraes los hitos narrativos de una conversación de rol y los compilas en una memoria ' +
      'compacta. Conservas hechos, decisiones, promesas, objetos y relaciones. Descartas la ' +
      'prosa. Escribes en español, en viñetas, sin preámbulo.',
    messages: [
      {
        role: 'user',
        content: previousMemory
          ? `Memoria previa:\n${previousMemory}\n\nNuevos intercambios:\n${transcript}\n\nDevuelve la memoria actualizada.`
          : `Intercambios:\n${transcript}\n\nDevuelve la memoria.`,
      },
    ],
  });

  const block = response.content.find((b) => b.type === 'text');
  return block && block.type === 'text' ? block.text.trim() : (previousMemory ?? '');
}

/**
 * Resumen ejecutivo matutino (§7.4). Una llamada al día.
 *
 * Declara `fallbacks` del lado del servidor para que un rechazo del
 * clasificador no deje al Dashboard con un hueco.
 */
export async function summarizeHeadlines(
  headlines: { title: string; summary: string | null; source: string }[],
): Promise<string> {
  const listado = headlines
    .map((h, i) => `${i + 1}. [${h.source}] ${h.title}${h.summary ? `\n   ${h.summary}` : ''}`)
    .join('\n');

  const response = await anthropic().beta.messages.create({
    model: DEFAULT_MODEL,
    max_tokens: 2048,
    betas: ['server-side-fallback-2026-06-01'],
    fallbacks: [{ model: 'claude-opus-4-8' }],
    output_config: { effort: 'low' },
    system:
      'Redactas un resumen ejecutivo de tres párrafos sobre la actualidad económica colombiana ' +
      'a partir de titulares. Español neutro, tono sobrio, sin adjetivación innecesaria. No ' +
      'inventas cifras que no aparezcan en los titulares; si un dato no consta, no lo mencionas.',
    messages: [{ role: 'user', content: `Titulares de hoy:\n\n${listado}` }],
  } as Parameters<ReturnType<typeof anthropic>['beta']['messages']['create']>[0]);

  const block = (response as Anthropic.Message).content.find((b) => b.type === 'text');
  return block && block.type === 'text' ? block.text.trim() : '';
}
