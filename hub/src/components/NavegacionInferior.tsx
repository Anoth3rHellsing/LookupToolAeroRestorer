'use client';

import Link from 'next/link';
import { CheckSquare, Flame, LayoutDashboard, Plus, Wallet } from 'lucide-react';

/**
 * Navegación móvil (ARQUITECTURA.md §12.2).
 *
 * Cuatro accesos críticos más el botón central de captura rápida. Las
 * herramientas secundarias viven en el menú superior, no aquí: apretar
 * diez destinos en una barra de 390 px garantiza pulsaciones erróneas.
 *
 * El `paddingBottom` consume la zona segura inferior para que la barra de
 * gestos de iOS y Android no cubra los botones.
 */
const ACCESOS = [
  { href: '/', label: 'Foco', icon: LayoutDashboard },
  { href: '/tareas', label: 'Tareas', icon: CheckSquare },
  { href: '/finanzas', label: 'Finanzas', icon: Wallet },
  { href: '/habitos', label: 'Hábitos', icon: Flame },
];

export function NavegacionInferior() {
  return (
    <nav
      className="fixed inset-x-0 bottom-0 z-50 border-t lg:hidden"
      style={{
        borderColor: 'var(--borde)',
        background: 'var(--superficie)',
        paddingBottom: 'var(--safe-bottom)',
      }}
      aria-label="Navegación principal"
    >
      <div className="mx-auto grid max-w-2xl grid-cols-5 items-center px-2 py-1">
        {ACCESOS.slice(0, 2).map(({ href, label, icon: Icono }) => (
          <Link key={href} href={href} className="toque flex-col gap-0.5 text-[11px]">
            <Icono size={20} aria-hidden />
            <span>{label}</span>
          </Link>
        ))}

        <button
          type="button"
          className="toque mx-auto rounded-full text-slate-900"
          style={{ background: 'var(--acento)' }}
          aria-label="Captura rápida"
        >
          <Plus size={22} aria-hidden />
        </button>

        {ACCESOS.slice(2).map(({ href, label, icon: Icono }) => (
          <Link key={href} href={href} className="toque flex-col gap-0.5 text-[11px]">
            <Icono size={20} aria-hidden />
            <span>{label}</span>
          </Link>
        ))}
      </div>
    </nav>
  );
}
