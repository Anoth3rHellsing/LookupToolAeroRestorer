import type { Metadata, Viewport } from 'next';
import './globals.css';
import { NavegacionLateral } from '@/components/NavegacionLateral';
import { NavegacionInferior } from '@/components/NavegacionInferior';

export const metadata: Metadata = {
  title: 'Hub Personal',
  description: 'Centro de control personal: finanzas, productividad, mercados y conocimiento.',
};

/**
 * `viewportFit: 'cover'` es lo que ACTIVA las funciones
 * `env(safe-area-inset-*)`. Sin él las variables valen cero y toda la
 * previsión de zonas seguras de `globals.css` queda inerte.
 */
export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
  themeColor: '#0b1220',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <body>
        <div className="flex min-h-dvh">
          {/* Barra lateral: sólo a partir de 1024 px (§12.2). */}
          <NavegacionLateral />

          <main
            className="min-w-0 flex-1 pb-24 lg:pb-8"
            style={{
              paddingLeft: 'var(--safe-left)',
              paddingRight: 'var(--safe-right)',
              paddingTop: 'var(--safe-top)',
            }}
          >
            {children}
          </main>
        </div>

        {/* Barra inferior: sólo por debajo de 1024 px. */}
        <NavegacionInferior />
      </body>
    </html>
  );
}
