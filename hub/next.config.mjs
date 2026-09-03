/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  // El worker importa el esquema; excluir `pg` del empaquetado del
  // servidor evita duplicar el driver de PostgreSQL en el bundle.
  serverExternalPackages: ['pg'],
  poweredByHeader: false,
};

export default config;
