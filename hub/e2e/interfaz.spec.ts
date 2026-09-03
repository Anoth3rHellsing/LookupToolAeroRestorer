import { expect, test } from '@playwright/test';

/**
 * Verificación estructural y de interacción (ARQUITECTURA.md §12.2).
 *
 * Cada comprobación corresponde a una regla del protocolo. No son
 * capturas de pantalla que alguien deba mirar: son aserciones que
 * rompen la compilación.
 */

const RUTAS = ['/'];

for (const ruta of RUTAS) {
  test.describe(`ruta ${ruta}`, () => {
    test('no desborda horizontalmente', async ({ page }) => {
      await page.goto(ruta);
      // El defecto más difícil de localizar después: un solo elemento
      // que desborde produce el desplazamiento horizontal fantasma.
      const desbordamiento = await page.evaluate(() => {
        const el = document.documentElement;
        return { scroll: el.scrollWidth, cliente: el.clientWidth };
      });
      expect(desbordamiento.scroll, `scrollWidth ${desbordamiento.scroll} > clientWidth ${desbordamiento.cliente}`)
        .toBeLessThanOrEqual(desbordamiento.cliente + 1);
    });

    test('todo elemento pulsable cumple 44x44 px', async ({ page }) => {
      await page.goto(ruta);
      const pequenos = await page.evaluate(() => {
        const seleccionables = document.querySelectorAll('a, button, input, select, [role="button"]');
        const fallos: string[] = [];
        for (const el of seleccionables) {
          const r = el.getBoundingClientRect();
          // Un elemento oculto no tiene caja: no se evalúa.
          if (r.width === 0 && r.height === 0) continue;
          if (r.width < 44 || r.height < 44) {
            fallos.push(`${el.tagName.toLowerCase()} "${el.textContent?.trim().slice(0, 24)}" ${Math.round(r.width)}x${Math.round(r.height)}`);
          }
        }
        return fallos;
      });
      expect(pequenos, `Áreas táctiles insuficientes: ${pequenos.join('; ')}`).toEqual([]);
    });

    test('todo campo numérico declara inputmode', async ({ page }) => {
      await page.goto(ruta);
      const sinInputmode = await page.evaluate(() => {
        const campos = document.querySelectorAll('input[type="number"], input[data-money]');
        return [...campos].filter((c) => !c.getAttribute('inputmode')).length;
      });
      expect(sinInputmode).toBe(0);
    });
  });
}

test.describe('navegación adaptativa', () => {
  test('exactamente una barra de navegación es visible en cada viewport', async ({ page }, info) => {
    await page.goto('/');
    const lateral = await page.locator('aside').isVisible().catch(() => false);
    const inferior = await page.locator('nav[aria-label="Navegación principal"]').isVisible().catch(() => false);

    // El punto de corte es único y compartido. Si los componentes
    // divergieran, existiría un rango de anchos SIN navegación alguna, o
    // con las dos a la vez.
    expect([lateral, inferior].filter(Boolean).length,
      `${info.project.name}: lateral=${lateral} inferior=${inferior}`).toBe(1);

    if (info.project.name === 'escritorio') expect(lateral).toBe(true);
    else expect(inferior).toBe(true);
  });
});
