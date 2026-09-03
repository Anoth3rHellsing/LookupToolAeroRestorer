import Link from 'next/link';
import {
  BarChart3, BookOpen, CheckSquare, Dumbbell, FileText, Flame,
  Gamepad2, LayoutDashboard, Settings, Wallet,
} from 'lucide-react';

const ENLACES = [
  { href: '/', label: 'Foco', icon: LayoutDashboard },
  { href: '/tareas', label: 'Tareas', icon: CheckSquare },
  { href: '/finanzas', label: 'Finanzas', icon: Wallet },
  { href: '/habitos', label: 'Hábitos', icon: Flame },
  { href: '/entrenamiento', label: 'Entrenamiento', icon: Dumbbell },
  { href: '/estudio', label: 'Estudio', icon: BookOpen },
  { href: '/mercados', label: 'Mercados', icon: BarChart3 },
  { href: '/archivos', label: 'Archivos', icon: FileText },
  { href: '/play', label: 'Entretenimiento', icon: Gamepad2 },
  { href: '/ajustes', label: 'Ajustes', icon: Settings },
];

/**
 * Navegación de escritorio (ARQUITECTURA.md §12.2).
 *
 * Oculta por debajo de 1024 px, donde la sustituye `NavegacionInferior`.
 * El punto de corte es único y compartido por ambos componentes: si
 * divergieran, existiría un rango de anchos sin navegación alguna.
 */
export function NavegacionLateral() {
  return (
    <aside
      className="hidden w-60 shrink-0 border-r lg:block"
      style={{ borderColor: 'var(--borde)', background: 'var(--superficie)' }}
    >
      <div className="sticky top-0 flex flex-col gap-1 p-4" style={{ paddingTop: 'calc(1rem + var(--safe-top))' }}>
        <p className="mb-4 px-2 text-sm font-semibold tracking-wide" style={{ color: 'var(--texto-tenue)' }}>
          HUB PERSONAL
        </p>
        {ENLACES.map(({ href, label, icon: Icono }) => (
          <Link
            key={href}
            href={href}
            className="toque justify-start gap-3 rounded-lg px-3 py-2 text-sm transition-colors hover:bg-white/5"
          >
            <Icono size={18} aria-hidden />
            <span>{label}</span>
          </Link>
        ))}
      </div>
    </aside>
  );
}
