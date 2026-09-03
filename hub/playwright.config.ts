import { defineConfig, devices } from '@playwright/test';

/**
 * Automatización de la doble verificación de interfaces
 * (ARQUITECTURA.md §12.2).
 *
 * El protocolo original era enteramente MANUAL, que era su única
 * debilidad: un protocolo que depende de que alguien se acuerde de
 * ejecutarlo no protege de las regresiones, protege de las regresiones
 * los días que hay tiempo.
 *
 * Tres viewports que cubren los tres regímenes de la matriz de
 * adaptación: móvil vertical, tableta y escritorio.
 */
export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: process.env.E2E_BASE_URL ?? 'http://127.0.0.1:3111',
    launchOptions: { executablePath: process.env.CHROMIUM_PATH || undefined },
  },
  projects: [
    { name: 'movil',      use: { ...devices['Pixel 7'], viewport: { width: 390, height: 844 } } },
    { name: 'tableta',    use: { ...devices['Desktop Chrome'], viewport: { width: 820, height: 1180 } } },
    { name: 'escritorio', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
  ],
});
