import { sha256 } from '../crypto';

/**
 * Canonicalización de URL (ARQUITECTURA.md §7.3).
 *
 * CORRECCIÓN respecto a la v1, que calculaba el hash de desduplicación
 * sobre la URL CRUDA. Ese criterio falla en cuanto un medio añade
 * parámetros de campaña: la misma nota entra dos veces, y el Dashboard
 * muestra duplicados que el usuario percibe —con razón— como un fallo.
 */

const TRACKING_PARAMS = [
  'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content', 'utm_id',
  'fbclid', 'gclid', 'gbraid', 'wbraid', 'msclkid', 'dclid', 'yclid',
  'mc_cid', 'mc_eid', 'igshid', 'ref', 'ref_src', 'source', 's', 'cmpid',
  '_ga', '_gl', 'spm', 'scid',
];

/**
 * Reduce una URL a su forma canónica:
 *
 *   1. Esquema y host en minúsculas; se descarta el prefijo `www.`.
 *   2. Se eliminan los parámetros de seguimiento conocidos.
 *   3. Los parámetros restantes se ordenan alfabéticamente, para que el
 *      orden en que los emita el medio no genere hashes distintos.
 *   4. Se elimina el fragmento y la barra final.
 *
 * Una URL que no se pueda analizar se devuelve tal cual: es preferible un
 * duplicado ocasional a perder el artículo por completo.
 */
export function canonicalizeUrl(input: string): string {
  let url: URL;
  try {
    url = new URL(input.trim());
  } catch {
    return input.trim();
  }

  if (url.protocol !== 'http:' && url.protocol !== 'https:') return input.trim();

  url.protocol = url.protocol.toLowerCase();
  url.hostname = url.hostname.toLowerCase().replace(/^www\./, '');
  url.hash = '';

  for (const param of TRACKING_PARAMS) url.searchParams.delete(param);

  const sorted = [...url.searchParams.entries()].sort(([a], [b]) => a.localeCompare(b));
  url.search = '';
  for (const [k, v] of sorted) url.searchParams.append(k, v);

  let out = url.toString();
  // La barra final no distingue recursos; el `?` huérfano tampoco.
  out = out.replace(/\?$/, '');
  if (url.pathname !== '/' && out.endsWith('/')) out = out.slice(0, -1);
  return out;
}

export function urlHash(input: string): string {
  return sha256(canonicalizeUrl(input));
}

/**
 * Título normalizado para el desempate secundario.
 *
 * Atrapa la republicación con URL nueva, que el hash por sí solo deja
 * pasar. Sostiene el índice único
 * `(source_id, title_normalized, published_on)`.
 */
export function normalizeTitle(title: string): string {
  return title
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}
