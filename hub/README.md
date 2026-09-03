# Hub Personal

Centro de control personal: almacenamiento en la nube, productividad,
finanzas multimoneda, ingesta de mercados, segundo cerebro,
entretenimiento conversacional y pasarela de ingesta para agentes
autónomos.

## Documentación

| Documento | Contenido |
|---|---|
| [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md) | Arquitectura v2 completa, con el registro de correcciones respecto a la v1 |
| [`docs/ESQUEMA.md`](docs/ESQUEMA.md) | Referencia del modelo de datos |

## Puesta en marcha

```bash
npm install
cp .env.example .env        # y rellenar
npm run db:migrate
npm run dev                 # despliegue «web»
npm run worker              # despliegue «worker», en otro proceso
```

## Topología

Dos despliegues sobre una sola base de código (ARQUITECTURA.md §2):

| Despliegue | Infraestructura | Responsabilidad |
|---|---|---|
| `web` | Replit Autoscale | Interfaz, API, SSE, pasarela de agentes |
| `worker` | Replit Reserved VM | Planificador, ingesta, sincronización |

La separación no es estética: un despliegue Autoscale **escala a cero**,
y un contenedor apagado no ejecuta el temporizador que sincroniza la TRM
a las 18:00. Ése era el defecto capital del diseño original.

## Estado

| Componente | Estado | Verificación realizada |
|---|---|---|
| Esquema y migraciones | Completo | Aplicado sobre PostgreSQL 16.13; restricciones y disparadores probados con inserciones reales |
| Aritmética financiera | Completo | 23 pruebas unitarias |
| Criptografía y tokens | Completo | 17 pruebas unitarias |
| Ensamblado de prompts | Completo | 15 pruebas unitarias |
| Rachas, 1RM, URL canónica | Completo | 33 pruebas unitarias |
| Pasarela de agentes | Completo | 9 casos de extremo a extremo contra el servidor de producción |
| Ingesta de TRM | Completo | Ejecutada contra datos.gov.co; dato real persistido con su rango de vigencia |
| Doble verificación de interfaces | Automatizada | 12 comprobaciones en Chromium, 3 viewports |
| Canal SSE | Implementado | Sin prueba automatizada todavía |
| Armazón de interfaz | Puntos de corte definitivos | Datos de muestra |
| Worker | Planificador y trabajo de TRM | Resto de trabajos pendiente |
| Autenticación | Pendiente | Fase 1 |
| Almacenamiento de objetos | Pendiente | Fase 1 |

## Verificación

```bash
npm test          # 88 pruebas unitarias
npm run typecheck # comprobación de tipos
npm run build     # compilación de producción
npm run test:e2e  # interfaces (requiere el servidor en marcha)
```

En este entorno, Playwright necesita que se le indique el ejecutable:

```bash
CHROMIUM_PATH=/opt/pw-browsers/chromium-1194/chrome-linux/chrome npm run test:e2e
```

### Nota sobre la versión de TypeScript

Está fijada a `^5.9` deliberadamente. TypeScript 7 es el port nativo y su
paquete no expone la API JavaScript del compilador (`ts.sys`,
`ts.readConfigFile`) de la que Next.js depende para leer
`compilerOptions.paths`. Con TypeScript 7 instalado, Next falla al cargar
`next.config.ts` y descarta los alias de ruta **en silencio**, produciendo
errores de «módulo no encontrado» sin relación aparente con la causa.

## Correcciones que este código materializa

Cada una responde a un defecto del documento de arquitectura original y
está blindada por una prueba que fallaría si se reintrodujese:

| Corrección | Dónde | Prueba |
|---|---|---|
| Cuota como anualidad, no división simple | `src/lib/finance/amortization.ts` | «con interés, la cuota es MAYOR que capital/plazo» |
| Bloque `system` congelado y cacheable | `src/lib/claude.ts` | «el prefijo es idéntico byte a byte entre turnos» |
| Token opaco en lugar de bcrypt por petición | `src/lib/crypto.ts` | «verifica contra el hash almacenado» |
| Nonce único por cifrado | `src/lib/crypto.ts` | «EL NONCE ES ÚNICO POR OPERACIÓN» |
| Desduplicación por URL canónica | `src/lib/ingest/canonicalUrl.ts` | «los parámetros de campaña ya no duplican» |
| Racha congelada por «saltar» | `src/lib/habits/streak.ts` | «congela la racha, no la restablece» |
| TRM por rango de vigencia | `src/lib/providers/trm.ts` | Verificado en la base de datos |
| Frontera de día en zona local | `src/lib/time.ts` | Verificado en la base de datos |
