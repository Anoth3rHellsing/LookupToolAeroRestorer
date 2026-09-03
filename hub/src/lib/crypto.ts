import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
  timingSafeEqual,
} from 'node:crypto';

/**
 * Primitivas criptográficas (ARQUITECTURA.md §4.2 y §11.2).
 *
 * Principio rector: el secreto de máquina no se trata como contraseña
 * humana. Alta entropía -> hash rápido en tiempo constante. Baja
 * entropía -> argon2id.
 */

const ALGORITHM = 'aes-256-gcm';
const NONCE_BYTES = 12;
const FORMAT_VERSION = 'v1';

function key(): Buffer {
  const raw = process.env.ENCRYPTION_KEY;
  if (!raw) throw new Error('ENCRYPTION_KEY no está definida.');
  const k = Buffer.from(raw, 'base64');
  if (k.length !== 32) {
    throw new Error(`ENCRYPTION_KEY debe ser de 32 bytes en base64; recibidos ${k.length}.`);
  }
  return k;
}

/**
 * Cifra con AES-256-GCM.
 *
 * El nonce es de 12 bytes ALEATORIOS Y ÚNICOS por operación. Reutilizarlo
 * con la misma clave rompe GCM por completo: es el fallo clásico de estas
 * implementaciones, y por eso se genera aquí y nunca se recibe como
 * parámetro.
 *
 * Formato: `v1.<nonce>.<ciphertext>.<authTag>`, todo en base64. El
 * prefijo de versión permite rotar clave o algoritmo sin ambigüedad.
 */
export function encrypt(plaintext: string): string {
  const nonce = randomBytes(NONCE_BYTES);
  const cipher = createCipheriv(ALGORITHM, key(), nonce);
  const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return [
    FORMAT_VERSION,
    nonce.toString('base64'),
    ciphertext.toString('base64'),
    authTag.toString('base64'),
  ].join('.');
}

/**
 * Descifra y VERIFICA la etiqueta de autenticación.
 *
 * Un fallo de autenticación es un error, nunca un descifrado parcial: si
 * el texto cifrado fue manipulado, no hay nada que devolver.
 */
export function decrypt(payload: string): string {
  const parts = payload.split('.');
  if (parts.length !== 4) throw new Error('Formato de texto cifrado inválido.');
  const [version, nonceB64, ciphertextB64, authTagB64] = parts as [string, string, string, string];
  if (version !== FORMAT_VERSION) throw new Error(`Versión de cifrado no soportada: ${version}`);

  const decipher = createDecipheriv(ALGORITHM, key(), Buffer.from(nonceB64, 'base64'));
  decipher.setAuthTag(Buffer.from(authTagB64, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertextB64, 'base64')),
    decipher.final(),
  ]).toString('utf8');
}

/** Token opaco de 32 bytes (256 bits) en base64url. */
export function generateToken(): string {
  return randomBytes(32).toString('base64url');
}

export function sha256(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

/**
 * Comparación en tiempo constante de dos digests hexadecimales.
 *
 * `timingSafeEqual` exige búferes de igual longitud, de modo que se
 * comparan los HASHES y no los valores en claro: así la longitud del
 * secreto tampoco se filtra por el canal temporal.
 */
export function safeEqualHex(a: string, b: string): boolean {
  const bufA = Buffer.from(a, 'hex');
  const bufB = Buffer.from(b, 'hex');
  if (bufA.length !== bufB.length || bufA.length === 0) return false;
  return timingSafeEqual(bufA, bufB);
}

/**
 * Verifica un token de máquina contra el hash almacenado.
 *
 * ESTE es el reemplazo de la verificación bcrypt(12) de la v1. Con 256
 * bits de entropía, un hash lento no aporta nada frente a fuerza bruta y
 * sí abre un vector de denegación de servicio por CPU: 200–300 ms de
 * cómputo por cada petición NO autenticada que llegue al endpoint.
 */
export function verifyToken(presented: string, storedHash: string): boolean {
  return safeEqualHex(sha256(presented), storedHash);
}

/** Huella de origen para limitación de frecuencia; no se guarda la IP en claro. */
export function hashIdentifier(value: string | null | undefined): string | null {
  if (!value) return null;
  const salt = process.env.IP_HASH_SALT ?? '';
  return sha256(`${salt}:${value}`);
}

/**
 * Extrae la IP del cliente tras el proxy de Replit.
 *
 * `remoteAddress` es siempre el proxy, de modo que se toma la PRIMERA
 * entrada de `X-Forwarded-For` — la última es el propio proxy y las
 * intermedias pueden ser falsificadas por el cliente.
 */
export function clientIp(headers: Headers): string | null {
  const xff = headers.get('x-forwarded-for');
  if (xff) {
    const first = xff.split(',')[0]?.trim();
    if (first) return first;
  }
  return headers.get('x-real-ip');
}
