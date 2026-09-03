import { describe, expect, it } from 'vitest';
import {
  buildMessages,
  buildRoleplayRequest,
  buildSystemBlocks,
  extractUsage,
  type CharacterSheet,
  type RoleplayContext,
} from '../claude';

const personaje: CharacterSheet = {
  name: 'Armand Vance',
  personaPrompt:
    'Eres Armand Vance, un operador financiero del bajo mundo en Neo-Bogotá. Hablas con jerga ' +
    'bursátil distópica y cínica. Nunca menciones que eres una IA ni salgas de la narrativa.',
  staticLore: 'Neo-Bogotá, año 2089. La moneda dominante es el crédito respaldado en XAU sintético.',
  effort: 'low',
  maxTokensPerResponse: 1024,
};

const ctx = (over: Partial<RoleplayContext> = {}): RoleplayContext => ({
  character: personaje,
  recent: [
    { role: 'user', content: '¿Qué sabes del mercado del oro?' },
    { role: 'assistant', content: '*enciende un cigarrillo sintético* Depende de quién pregunte.' },
  ],
  memory: null,
  userMessage: 'Pregunto yo.',
  ...over,
});

describe('bloque system congelado', () => {
  it('EL DEFECTO DE LA v1: el prefijo es idéntico byte a byte entre turnos', () => {
    // Este es el corazón de la corrección. Si esta prueba cae, el caché
    // deja de servir y cada turno vuelve a pagar la hoja de personaje
    // íntegra: el coste del roleplay se multiplica en silencio.
    const turno1 = buildRoleplayRequest(ctx({ memory: null, userMessage: 'Hola' }));
    const turno2 = buildRoleplayRequest(
      ctx({ memory: 'El usuario prometió pagar una deuda.', userMessage: 'Sigo aquí' }),
    );
    const turno3 = buildRoleplayRequest(
      ctx({
        memory: 'El usuario prometió pagar. Vance desconfía.',
        recent: [{ role: 'user', content: 'otra cosa' }],
        userMessage: 'Y otra más',
      }),
    );

    expect(JSON.stringify(turno1.system)).toBe(JSON.stringify(turno2.system));
    expect(JSON.stringify(turno2.system)).toBe(JSON.stringify(turno3.system));
  });

  it('lleva el punto de corte del caché', () => {
    const blocks = buildSystemBlocks(personaje);
    expect(blocks).toHaveLength(1);
    expect(blocks[0]!.cache_control).toEqual({ type: 'ephemeral' });
  });

  it('incluye persona y lore permanente', () => {
    const texto = buildSystemBlocks(personaje)[0]!.text;
    expect(texto).toContain('Armand Vance');
    expect(texto).toContain('XAU sintético');
  });

  it('NO contiene la memoria de la conversación', () => {
    // La memoria en `system` era exactamente el error de la v1.
    const texto = buildSystemBlocks(personaje)[0]!.text;
    expect(texto).not.toContain('Memoria');
  });

  it('omite el encabezado de lore cuando no hay lore', () => {
    const texto = buildSystemBlocks({ ...personaje, staticLore: '' })[0]!.text;
    expect(texto).not.toContain('Contexto permanente');
  });
});

describe('array de mensajes', () => {
  it('coloca la memoria como ÚLTIMA entrada, tras el mensaje del usuario', () => {
    const msgs = buildMessages(ctx({ memory: 'Vance debe un favor.' }));
    const ultimo = msgs.at(-1)!;
    expect(ultimo.role).toBe('system');
    expect(String(ultimo.content)).toContain('Vance debe un favor');
    // La entrada previa debe ser del usuario: un mensaje system
    // intraconversacional no puede seguir a cualquier cosa.
    expect(msgs.at(-2)!.role).toBe('user');
  });

  it('omite el bloque de memoria si no la hay', () => {
    const msgs = buildMessages(ctx({ memory: null }));
    expect(msgs.every((m) => m.role !== 'system')).toBe(true);
    expect(msgs.at(-1)!.role).toBe('user');
  });

  it('trata la memoria en blanco como ausencia de memoria', () => {
    expect(buildMessages(ctx({ memory: '   ' })).every((m) => m.role !== 'system')).toBe(true);
  });

  it('conserva el orden cronológico del historial', () => {
    const msgs = buildMessages(ctx());
    expect(msgs[0]!.content).toContain('mercado del oro');
    expect(msgs[1]!.role).toBe('assistant');
    expect(msgs[2]!.content).toBe('Pregunto yo.');
  });

  it('nunca deja el mensaje system en primera posición', () => {
    // No es válido como messages[0].
    const msgs = buildMessages(ctx({ recent: [], memory: 'algo' }));
    expect(msgs[0]!.role).not.toBe('system');
  });
});

describe('parámetros de la petición', () => {
  it('usa pensamiento adaptativo y esfuerzo, NO parámetros de muestreo', () => {
    // `temperature`, `top_p` y `top_k` fueron retirados y devuelven 400.
    // La hoja de personaje de la v1 fijaba temperature: 0.85.
    const req = buildRoleplayRequest(ctx()) as Record<string, unknown>;
    expect(req.thinking).toEqual({ type: 'adaptive' });
    expect(req.output_config).toEqual({ effort: 'low' });
    expect(req).not.toHaveProperty('temperature');
    expect(req).not.toHaveProperty('top_p');
    expect(req).not.toHaveProperty('top_k');
  });

  it('respeta el límite de salida de la hoja de personaje', () => {
    expect(buildRoleplayRequest(ctx()).max_tokens).toBe(1024);
  });
});

describe('extractUsage', () => {
  it('recoge la telemetría de caché', () => {
    const u = extractUsage({
      input_tokens: 100,
      output_tokens: 50,
      cache_read_input_tokens: 900,
      cache_creation_input_tokens: 0,
    } as never);
    expect(u).toEqual({
      inputTokens: 100, outputTokens: 50, cacheReadTokens: 900, cacheWriteTokens: 0,
    });
  });

  it('tolera campos ausentes', () => {
    expect(extractUsage({ input_tokens: 1, output_tokens: 2 } as never).cacheReadTokens).toBe(0);
  });
});
