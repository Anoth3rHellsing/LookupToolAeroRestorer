import { dec } from '../money';
import type { Quote, QuoteProvider } from './types';

/**
 * Tasa de Cambio Representativa del Mercado (ARQUITECTURA.md §7.2).
 *
 * Origen oficial: Datos Abiertos de Colombia (Socrata), conjunto
 * `32sa-8pi3`, certificado por la Superintendencia Financiera.
 *
 * PRECISIÓN QUE LA v1 PASABA POR ALTO: la TRM es válida para un RANGO de
 * vigencia, no para un día suelto. El registro trae `vigenciadesde` y
 * `vigenciahasta`; un valor certificado un viernes rige también sábado y
 * domingo. Por eso `Quote` transporta el rango y no una sola fecha.
 */

const SOCRATA_URL = 'https://www.datos.gov.co/resource/32sa-8pi3.json';

interface SocrataRow {
  valor: string;
  vigenciadesde: string;
  vigenciahasta: string;
}

export const socrataTrm: QuoteProvider = {
  name: 'socrata',
  async fetch(signal) {
    const url = `${SOCRATA_URL}?$order=vigenciadesde%20DESC&$limit=1`;
    const res = await fetch(url, { signal, headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);

    const rows = (await res.json()) as SocrataRow[];
    const row = rows[0];
    if (!row) throw new Error('respuesta vacía');

    return {
      value: dec(row.valor),
      asOf: new Date(row.vigenciadesde),
      source: 'socrata',
      validFrom: row.vigenciadesde.slice(0, 10),
      validTo: row.vigenciahasta.slice(0, 10),
    };
  },
};

interface DolarApiRow { venta: number; fechaActualizacion: string }

/** Respaldo de contingencia ante indisponibilidad del servicio estatal. */
export const dolarApiTrm: QuoteProvider = {
  name: 'dolarapi',
  async fetch(signal) {
    const res = await fetch('https://co.dolarapi.com/v1/dolares/oficial', {
      signal,
      headers: { Accept: 'application/json' },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);

    const row = (await res.json()) as DolarApiRow;
    const asOf = new Date(row.fechaActualizacion);
    const day = asOf.toISOString().slice(0, 10);

    // El respaldo no publica rango de vigencia, de modo que se asume un
    // solo día. La columna `source` deja constancia de que este dato es
    // menos preciso que el oficial.
    return { value: dec(row.venta), asOf, source: 'dolarapi', validFrom: day, validTo: day };
  },
};

export const TRM_PROVIDERS: QuoteProvider[] = [socrataTrm, dolarApiTrm];

/** Resuelve qué TRM regía en una fecha dada, respetando el rango. */
export function trmAppliesTo(quote: Quote, isoDate: string): boolean {
  if (!quote.validFrom || !quote.validTo) return false;
  return isoDate >= quote.validFrom && isoDate <= quote.validTo;
}
