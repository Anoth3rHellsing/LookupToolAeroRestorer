import { describe, expect, it } from 'vitest';
import { canonicalizeUrl, normalizeTitle, urlHash } from '../canonicalUrl';

describe('canonicalizeUrl', () => {
  it('EL DEFECTO DE LA v1: los parámetros de campaña ya no duplican', () => {
    const limpia = 'https://www.eltiempo.com/economia/trm-hoy-123';
    const conUtm = `${limpia}?utm_source=twitter&utm_medium=social&utm_campaign=trm`;
    expect(urlHash(conUtm)).toBe(urlHash(limpia));
  });

  it('normaliza el prefijo www y el esquema', () => {
    expect(urlHash('https://www.portafolio.co/a')).toBe(urlHash('https://portafolio.co/a'));
  });

  it('no depende del orden de los parámetros significativos', () => {
    expect(urlHash('https://x.co/a?b=2&a=1')).toBe(urlHash('https://x.co/a?a=1&b=2'));
  });

  it('descarta el fragmento y la barra final', () => {
    expect(canonicalizeUrl('https://x.co/nota/#seccion')).toBe('https://x.co/nota');
  });

  it('CONSERVA los parámetros significativos', () => {
    // Un identificador de artículo no es seguimiento: eliminarlo
    // fusionaría notas distintas en una sola.
    expect(canonicalizeUrl('https://x.co/ver?id=99')).toContain('id=99');
    expect(urlHash('https://x.co/ver?id=99')).not.toBe(urlHash('https://x.co/ver?id=100'));
  });

  it('distingue rutas distintas', () => {
    expect(urlHash('https://x.co/a')).not.toBe(urlHash('https://x.co/b'));
  });

  it('devuelve la entrada intacta si no es analizable', () => {
    expect(canonicalizeUrl('esto no es una url')).toBe('esto no es una url');
    expect(canonicalizeUrl('javascript:alert(1)')).toBe('javascript:alert(1)');
  });

  it('conserva la barra de la raíz', () => {
    expect(canonicalizeUrl('https://x.co/')).toBe('https://x.co/');
  });
});

describe('normalizeTitle', () => {
  it('atrapa la republicación con URL nueva', () => {
    expect(normalizeTitle('El dólar cerró al alza')).toBe(normalizeTitle('EL DOLAR CERRO AL ALZA'));
  });

  it('ignora la puntuación y los espacios redundantes', () => {
    expect(normalizeTitle('¿Sube  la TRM?')).toBe('sube la trm');
  });

  it('no fusiona titulares realmente distintos', () => {
    expect(normalizeTitle('El dólar sube')).not.toBe(normalizeTitle('El dólar baja'));
  });
});
