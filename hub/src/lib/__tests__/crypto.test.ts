import { beforeAll, describe, expect, it } from 'vitest';
import { randomBytes } from 'node:crypto';
import { clientIp, decrypt, encrypt, generateToken, safeEqualHex, sha256, verifyToken } from '../crypto';

beforeAll(() => {
  process.env.ENCRYPTION_KEY = randomBytes(32).toString('base64');
});

describe('AES-256-GCM', () => {
  it('descifra lo que cifró', () => {
    const secreto = '1//0abcdefRefreshTokenDeGoogle';
    expect(decrypt(encrypt(secreto))).toBe(secreto);
  });

  it('EL NONCE ES ÚNICO POR OPERACIÓN', () => {
    // Reutilizar el nonce con la misma clave rompe GCM por completo. Es
    // el fallo clásico de estas implementaciones y esta prueba existe
    // para que una refactorización futura no lo reintroduzca.
    const nonces = new Set<string>();
    for (let i = 0; i < 500; i += 1) nonces.add(encrypt('mismo texto').split('.')[1]!);
    expect(nonces.size).toBe(500);
  });

  it('dos cifrados del mismo texto difieren', () => {
    expect(encrypt('x')).not.toBe(encrypt('x'));
  });

  it('lleva prefijo de versión y cuatro segmentos', () => {
    const parts = encrypt('x').split('.');
    expect(parts).toHaveLength(4);
    expect(parts[0]).toBe('v1');
  });

  it('rechaza el texto cifrado manipulado en lugar de descifrar a medias', () => {
    const [v, nonce, ct, tag] = encrypt('confidencial').split('.') as [string, string, string, string];
    const alterado = Buffer.from(ct, 'base64');
    alterado.writeUInt8(alterado.readUInt8(0) ^ 0xff, 0);
    expect(() => decrypt([v, nonce, alterado.toString('base64'), tag].join('.'))).toThrow();
  });

  it('rechaza una etiqueta de autenticación falsificada', () => {
    const [v, nonce, ct] = encrypt('confidencial').split('.') as [string, string, string];
    const tagFalsa = randomBytes(16).toString('base64');
    expect(() => decrypt([v, nonce, ct, tagFalsa].join('.'))).toThrow();
  });

  it('rechaza una versión de formato desconocida', () => {
    const partes = encrypt('x').split('.');
    partes[0] = 'v9';
    expect(() => decrypt(partes.join('.'))).toThrow(/no soportada/);
  });

  it('rechaza una clave que no mida 32 bytes', () => {
    const anterior = process.env.ENCRYPTION_KEY;
    process.env.ENCRYPTION_KEY = randomBytes(16).toString('base64');
    expect(() => encrypt('x')).toThrow(/32 bytes/);
    process.env.ENCRYPTION_KEY = anterior;
  });
});

describe('tokens de máquina', () => {
  it('genera 32 bytes de entropía', () => {
    expect(Buffer.from(generateToken(), 'base64url')).toHaveLength(32);
  });

  it('no se repite', () => {
    const s = new Set<string>();
    for (let i = 0; i < 1000; i += 1) s.add(generateToken());
    expect(s.size).toBe(1000);
  });

  it('verifica contra el hash almacenado', () => {
    const token = generateToken();
    expect(verifyToken(token, sha256(token))).toBe(true);
    expect(verifyToken(generateToken(), sha256(token))).toBe(false);
  });

  it('no falla ante entradas degeneradas', () => {
    expect(verifyToken('', sha256('x'))).toBe(false);
    expect(safeEqualHex('', '')).toBe(false);
    expect(safeEqualHex('aabb', 'aabbcc')).toBe(false);
  });
});

describe('clientIp', () => {
  it('toma la PRIMERA entrada de X-Forwarded-For', () => {
    // La última es el propio proxy de Replit; las intermedias pueden ser
    // falsificadas por el cliente.
    const h = new Headers({ 'x-forwarded-for': '203.0.113.7, 10.0.0.1, 10.0.0.2' });
    expect(clientIp(h)).toBe('203.0.113.7');
  });

  it('recurre a x-real-ip y luego a nulo', () => {
    expect(clientIp(new Headers({ 'x-real-ip': '198.51.100.4' }))).toBe('198.51.100.4');
    expect(clientIp(new Headers())).toBeNull();
  });
});
