# Hub Personal Integral — Arquitectura de Software v2

> **Estado del documento:** v2 (revisión correctiva de la v1).
> **Ámbito:** centro de control personal monousuario con almacenamiento en la nube,
> productividad, finanzas multimoneda, ingesta de mercados, segundo cerebro,
> entretenimiento conversacional y pasarela de ingesta para agentes autónomos.
> **Plataforma objetivo:** Replit (contenedores gestionados) + PostgreSQL (Neon).

---

## 0. Registro de cambios respecto a la v1

Esta versión conserva íntegramente el alcance funcional de la v1 y corrige los
defectos que impedirían su ejecución en producción. Los cambios sustantivos son:

| # | Área | Defecto en v1 | Corrección en v2 | Sección |
|---|------|---------------|------------------|---------|
| 1 | Despliegue | Procesos de fondo (cron, workers, SSE) sobre un contenedor que escala a cero | Topología de **dos despliegues**: `web` en Autoscale + `worker` en Reserved VM | [§2](#2-topología-de-despliegue) |
| 2 | Finanzas | `Cuota = Capital / Plazo` ignora el interés corriente | Fórmula de anualidad con rama explícita para 0 % | [§9.3](#93-diferimiento-en-cuotas) |
| 3 | IA | Modelos Claude 3.5 (descontinuados) | Familia Claude 5 / Haiku 4.5 con IDs vigentes | [§10.1](#101-selección-de-modelo) |
| 4 | IA | La memoria del roleplay se inyectaba en `system`, invalidando el caché en cada turno | `system` congelado y cacheado; memoria como **mensaje `system` intraconversacional** | [§10.3](#103-memoria-y-caché-de-prompts) |
| 5 | Seguridad | Verificación bcrypt(12) en cada petición de agente → vector de DoS por CPU | Token opaco de 32 bytes, hash SHA-256, comparación en tiempo constante | [§11.2](#112-autenticación-de-la-pasarela) |
| 6 | Seguridad | Enlace revocado seguía sirviendo el objeto mientras la firma S3 viviera | Firmas de 60 s + streaming por proxy para enlaces con contraseña | [§6.3](#63-revocación-y-fuga-post-expiración) |
| 7 | Datos | Sin esquema, sin `user_id`, sin índices | Esquema relacional completo y versionado | [§4](#4-modelo-de-identidad-y-tenencia) y `docs/ESQUEMA.md` |
| 8 | Calendar | `events.watch` sin renovación → sincronización muere en silencio | Sondeo incremental con `syncToken` como mecanismo primario | [§8.2](#82-sincronización-con-google-calendar) |
| 9 | Ingesta | Deduplicación por hash de URL cruda | Normalización canónica de URL antes del hash + desempate por título | [§7.3](#73-noticias-rssatom) |
| 10 | Operación | Sin observabilidad, respaldos ni presupuesto | `job_runs`, alertas de obsolescencia, sección de costes | [§13](#13-observabilidad-y-operación) |

---

## 1. Principios rectores

1. **El contenedor es desechable; el estado no vive en él.** Ningún dato de
   negocio reside en el sistema de archivos local ni en memoria de proceso.
   Postgres y el almacén de objetos son la única verdad.
2. **Una sola fuente de tiempo.** Todo instante se persiste como `timestamptz`
   en UTC. La noción de "día" se deriva siempre en `America/Bogota`.
3. **El dinero no es un número en coma flotante.** `numeric(20,4)` en la base de
   datos, aritmética decimal exacta en la aplicación.
4. **Degradación explícita antes que fallo silencioso.** Todo proveedor externo
   tiene fuente de respaldo y último-valor-bueno con marca de obsolescencia
   visible en la interfaz.
5. **El secreto de máquina no se trata como contraseña humana.** Alta entropía
   → hash rápido en tiempo constante. Baja entropía → argon2id.

---

## 2. Topología de despliegue

El defecto capital de la v1 era apoyar seis procesos periódicos y un canal SSE
persistente sobre un despliegue que, por definición, se apaga sin tráfico. Un
**Autoscale Deployment** de Replit escala a cero: sin peticiones entrantes no hay
proceso, y por tanto no hay temporizador que dispare la TRM a las 18:00.

La v2 separa responsabilidades en dos despliegues sobre la misma base de código:

```
┌──────────────────────────────────────────────────────────────┐
│  Repositorio único (monorepo TypeScript)                      │
└───────────────┬──────────────────────────┬───────────────────┘
                │                          │
    ┌───────────▼───────────┐   ┌──────────▼──────────────────┐
    │  DESPLIEGUE «web»     │   │  DESPLIEGUE «worker»        │
    │  Replit Autoscale     │   │  Replit Reserved VM         │
    │                       │   │  (proceso siempre residente)│
    │  · Next.js App Router │   │  · Planificador interno     │
    │  · API Routes         │   │  · Ingesta TRM / XAU / RSS  │
    │  · SSE al navegador   │   │  · Sync Google Calendar     │
    │  · Pasarela de agentes│   │  · Resumen matutino (Claude)│
    │  · Escala a cero      │   │  · Barrido de caducidades   │
    └───────────┬───────────┘   └──────────┬──────────────────┘
                │                          │
                └────────┬─────────────────┘
                         │
            ┌────────────▼─────────────┐    ┌──────────────────┐
            │  PostgreSQL (Neon)       │    │  Object Storage  │
            │  · Datos                 │    │  (Replit / R2)   │
            │  · LISTEN/NOTIFY (bus)   │    │  · Binarios      │
            │  · Cola de trabajos      │    └──────────────────┘
            └──────────────────────────┘
```

**Por qué un Reserved VM y no seis Scheduled Deployments.** Replit ofrece
despliegues programados, pero cada ciclo del sistema (TRM, XAU, RSS, digest,
Calendar, barrido) sería un despliegue independiente con su propio arranque en
frío y su propia facturación. Un único VM reservado con planificador interno es
más barato, arranca una sola vez, mantiene viva la conexión TCP a Postgres para
`LISTEN/NOTIFY` y permite un sondeo de Calendar de baja latencia. La alternativa
de despliegues programados queda documentada en [§13.4](#134-alternativa-de-despliegues-programados)
para quien prefiera no pagar un VM.

### 2.1 Bus de eventos en tiempo real

El Dashboard debe reaccionar al instante cuando el `worker` inserta una TRM nueva
o un agente externo deposita un informe. Con `web` en Autoscale pueden coexistir
varias instancias, de modo que un `EventEmitter` en memoria no basta.

**Mecanismo:** `LISTEN/NOTIFY` de PostgreSQL como bus de publicación.

- El `worker` ejecuta `NOTIFY hub_events, '<json>'` tras cada escritura relevante.
- Cada instancia de `web` que sostiene una conexión SSE mantiene un cliente
  `pg` dedicado en `LISTEN hub_events` y reenvía al navegador.
- **Advertencia operativa honesta:** Neon puede cerrar conexiones ociosas y
  suspender el endpoint. El cliente `LISTEN` debe implementar reconexión con
  retroceso exponencial, y al reconectar recuperar lo perdido leyendo la tabla
  `events` desde el último `id` conocido. Ese cursor hace el sistema correcto
  aunque el canal se caiga.
- **Respaldo:** si `LISTEN/NOTIFY` resulta inestable en el plan contratado, el
  endpoint SSE degrada a sondeo interno de la tabla `events` cada 3 s. El
  contrato con el navegador no cambia.

`Content-Type: text/event-stream`, `Cache-Control: no-cache, no-transform`,
`X-Accel-Buffering: no`, y un comentario `:keepalive` cada 20 s para atravesar
proxies intermedios.

### 2.2 Planificador del worker

| Trabajo | Cadencia | Zona | Notas |
|---|---|---|---|
| `trm.sync` | 18:05 y 19:30 COT, más reintento a las 06:00 | America/Bogota | La TRM del día siguiente se publica al final de la tarde |
| `xau.sync` | cada 20 min, lun 00:00 – vie 22:00 UTC | UTC | Fuera de horario de mercado no se consume cuota |
| `news.ingest` | cada 30 min | — | 4 canales RSS |
| `news.digest` | 06:00 COT | America/Bogota | Una llamada a Claude al día |
| `calendar.sync` | cada 10 min | — | Incremental con `syncToken` |
| `links.sweep` | cada hora | — | Marca enlaces caducados |
| `jobs.watchdog` | cada 15 min | — | Detecta datos obsoletos y alerta |

Cada ejecución escribe una fila en `job_runs` (inicio, fin, estado, error,
filas afectadas). Es la base de la observabilidad de [§13](#13-observabilidad-y-operación).

**Bloqueo de concurrencia.** Aunque hoy sólo hay un `worker`, cada trabajo toma
un `pg_try_advisory_lock` con clave derivada del nombre del trabajo. Si el VM se
reinicia durante un solapamiento, no habrá doble ingesta.

---

## 3. Selección tecnológica

| Capa | Tecnología | Justificación |
|---|---|---|
| Frontend / enrutado | Next.js 15 (App Router), React 19, Tailwind CSS 4 | Server Components para lo estático, Client Components para lo reactivo |
| Backend | Node.js 22 sobre Route Handlers y Server Actions | Un solo lenguaje, streams nativos, SSE sin capas intermedias |
| Base de datos | PostgreSQL 16 (Neon) | ACID, `numeric` exacto, `tsvector`, `LISTEN/NOTIFY`, `jsonb` |
| ORM | Drizzle ORM | Tipado extremo a extremo, migraciones SQL legibles, huella mínima |
| Driver | `pg` (TCP) en worker y rutas SSE; `@neondatabase/serverless` (HTTP) en lecturas de página | HTTP no soporta `LISTEN`; TCP sí |
| Objetos | Replit Object Storage o Cloudflare R2 (S3-compatible) | Ciclo de vida desacoplado del contenedor, URLs presignadas |
| IA | `@anthropic-ai/sdk` | Cliente oficial, caché de prompts, streaming |
| Validación | Zod | Frontera única de confianza para toda entrada externa |
| Componentes | Radix UI + Lucide | Accesibilidad correcta sin imponer estilos |
| Decimales | `decimal.js` | Aritmética monetaria exacta |
| Fechas | `date-fns` + `date-fns-tz` | Fronteras de día en `America/Bogota` |

---

## 4. Modelo de identidad y tenencia

La v1 no definía usuario alguno: ningún ejemplo llevaba `user_id`. Es la decisión
que más código condiciona y debe tomarse antes de la primera migración.

**Decisión: monousuario en producto, multiusuario en el esquema.**

Toda tabla de negocio lleva `user_id uuid not null references users(id) on delete cascade`.
El coste hoy es una columna y un índice; el coste de añadirla después es
reescribir cada consulta del sistema. El registro público permanece cerrado
(`ALLOW_SIGNUP=false`); el usuario se siembra por script.

### 4.1 Autenticación

- Credencial: correo + contraseña con **argon2id** (`m=19456 KiB, t=2, p=1`).
- Sesión: token opaco de 32 bytes aleatorios. Se almacena su SHA-256 en
  `sessions`; la cookie lleva el token en claro.
  Cookie `HttpOnly`, `Secure`, `SameSite=Lax`, 30 días con renovación deslizante.
- Segundo factor TOTP opcional (`users.totp_secret`, cifrado).
- Cierre de sesión global por borrado de filas en `sessions`.

No se adopta un proveedor externo de identidad: para un sistema de un solo
usuario añade una dependencia y una superficie de fallo sin contrapartida.

### 4.2 Gestión de secretos

Todo secreto vive en variables de entorno de Replit (Replit Secrets), nunca en
el repositorio. El inventario mínimo está en `hub/.env.example`.

`ENCRYPTION_KEY` es una clave de 32 bytes en base64 que protege, mediante
**AES-256-GCM**, los datos cifrados en reposo (hoy: el `refresh_token` de Google).
Contrato de cifrado, explícito porque es donde suelen fallar estas
implementaciones:

- Nonce de **12 bytes aleatorios y único por operación**. Reutilizarlo con la
  misma clave rompe GCM por completo.
- Formato persistido: `v1.<nonce_b64>.<ciphertext_b64>.<authTag_b64>`.
  El prefijo de versión permite rotar clave o algoritmo sin ambigüedad.
- El `authTag` se verifica siempre; un fallo de autenticación es un error, no
  un descifrado parcial.

---

## 5. Modelo de datos

El esquema completo —tablas, tipos, claves foráneas, índices, restricciones de
verificación y disparadores— se especifica en **`docs/ESQUEMA.md`** y se
implementa en `hub/src/db/schema/`. Resumen por dominio:

| Dominio | Tablas |
|---|---|
| Identidad | `users`, `sessions`, `oauth_accounts` |
| Archivos | `files`, `shared_links`, `share_access_log` |
| Productividad | `tasks`, `task_links` |
| Hábitos | `habits`, `habit_logs` |
| Entrenamiento | `workouts`, `workout_exercises`, `workout_sets`, `exercise_records` |
| Finanzas | `financial_accounts`, `transactions`, `credit_cards`, `card_cycles`, `installment_plans`, `installment_items`, `budgets` |
| Estudio | `subjects`, `topics`, `study_sessions` |
| Conocimiento | `notes`, `note_links` |
| Lectura | `bookmarks` |
| Entretenimiento | `characters`, `conversations`, `chat_messages`, `conversation_memories` |
| Mercados | `market_rates`, `market_commodities` |
| Noticias | `news_sources`, `news_articles`, `news_digests` |
| Pasarela | `agent_gateways`, `gateway_attempts`, `dashboard_announcements` |
| Operación | `events`, `job_runs` |

### 5.1 Convenciones transversales

- **Claves primarias:** `uuid` v7 generado en la aplicación (ordenable en el
  tiempo, buena localidad de índice, sin depender de extensiones de Postgres).
- **Auditoría:** toda tabla lleva `created_at` y `updated_at` (`timestamptz`,
  `default now()`), este último mantenido por disparador.
- **Borrado:** físico con `on delete cascade` desde `users`. Sólo `files` y
  `tasks` admiten borrado lógico (`deleted_at`) por tener valor de papelera.
- **Dinero:** `numeric(20,4)` más una columna `currency char(3)` adyacente.
  Jamás `float` ni `double precision`.
- **Enumerados:** tipos `enum` nativos de Postgres cuando el dominio es cerrado
  y estable; `text` con `check` cuando se prevé crecimiento.

---

## 6. Almacenamiento y distribución de archivos

### 6.1 Carga mediante URL presignada

El navegador nunca envía bytes al contenedor de Replit; los envía al almacén de
objetos. El contenedor sólo arbitra permisos y metadatos.

```
Cliente                        web (Next.js)                 Object Storage
   │                                │                              │
   │─ POST /api/files/presign ─────▶│                              │
   │   {name, size, mimeType}       │                              │
   │                                │─ valida cuota y tipo         │
   │                                │─ genera uuid v7 + objectKey  │
   │                                │─ firma PUT (TTL 5 min) ─────▶│
   │◀──── {uploadUrl, fileId} ──────│                              │
   │                                                               │
   │──────────────── PUT <uploadUrl> (bytes) ─────────────────────▶│
   │                                                               │
   │─ POST /api/files/{id}/commit ─▶│─ HEAD al objeto ────────────▶│
   │                                │  (verifica existencia y peso)│
   │◀──────── 201 Created ──────────│─ INSERT en files             │
```

Tres detalles que la v1 omitía y que sostienen la integridad del flujo:

1. **La fila se confirma, no se presupone.** `files` nace en estado `pending`.
   Sólo `commit` la pasa a `ready`, y sólo tras un `HEAD` que confirme que el
   objeto existe y su tamaño coincide con el declarado. Un cliente que abandone
   a mitad deja una fila `pending` que el barrido horario elimina.
2. **El `objectKey` lo decide el servidor**, con la forma
   `u/{userId}/{yyyy}/{mm}/{fileId}{ext}`. El nombre original es metadato, no ruta.
3. **La cuota se comprueba antes de firmar**, no después de subir.

### 6.2 Enlaces públicos

Ruta `/s/{token}`. El token son 32 bytes aleatorios en base64url; se persiste
únicamente su SHA-256 en `shared_links.token_hash`.

Políticas verificadas en orden estricto antes de servir:

| Política | Comportamiento | Código |
|---|---|---|
| Enlace inexistente o revocado | Respuesta genérica | `404` |
| Ventana de caducidad superada | — | `410 Gone` |
| Límite de descargas agotado | — | `410 Gone` |
| Contraseña requerida y ausente/incorrecta | Formulario, sin revelar si el recurso existe | `401` |
| Autorizado | Sirve el objeto | `200` |

- La contraseña del enlace se protege con **argon2id** (es un secreto humano de
  baja entropía; aquí sí corresponde un hash lento).
- `Content-Disposition` se decide por tipo MIME: `inline` para PDF e imágenes,
  `attachment` para todo lo demás. El nombre se sanea y se emite en
  `filename*=UTF-8''…` para admitir tildes.

### 6.3 Revocación y fuga post-expiración

**El defecto de la v1.** Si `/s/{token}` responde con un `302` hacia una URL
presignada de larga vida, el archivo permanece accesible por esa URL aunque el
enlace se revoque un segundo después. La revocación sería teatro.

**Corrección, por modalidad:**

- **Enlace sin contraseña:** se permite el redirección a URL presignada, pero
  con **TTL de 60 segundos**. La ventana de fuga queda acotada y no sobrevive a
  la revocación de forma significativa.
- **Enlace con contraseña o con límite de descargas:** el servidor **transmite
  el objeto por streaming** a través del Route Handler (`ReadableStream`, sin
  bufferizar en memoria). Nunca se expone una URL firmada, de modo que el
  control de acceso es efectivo en todo momento.

### 6.4 Semántica del contador de descargas

La v1 decía "decrece con cada acceso completado" sin definir *acceso*. Los
navegadores emiten peticiones por rangos y reintentan; contar peticiones
inflaría el contador y revocaría enlaces legítimos.

**Regla:** el contador se incrementa **una sola vez por token y por sesión de
descarga**, identificada por `(token_hash, ip_hash, user_agent_hash)` dentro de
una ventana de 10 minutos, y **sólo para peticiones sin cabecera `Range` o con
`Range` que comience en 0**. Cada intento se registra en `share_access_log`,
que además sirve de rastro de auditoría.

---

## 7. Ingesta de mercados e información

### 7.1 Contrato común de proveedores

Todo origen externo implementa la misma interfaz, de modo que el fallo de un
proveedor sea un cambio de implementación y no una reescritura:

```ts
interface Quote { value: Decimal; asOf: Date; source: string; }
interface QuoteProvider { name: string; fetch(): Promise<Quote>; }
```

El servicio de sincronización recorre los proveedores en orden de preferencia y
se detiene en el primer éxito. Si todos fallan:

- **No se escribe nada** y el último valor bueno permanece en la tabla.
- La interfaz muestra el valor con su antigüedad real ("TRM del 2 de septiembre").
- Si la antigüedad supera el umbral del dominio, el vigía de [§13](#13-observabilidad-y-operación)
  levanta una alerta en el Dashboard.

Nunca se muestra un hueco ni un cero. Un dato viejo etiquetado como viejo es
información; un cero es una mentira.

### 7.2 TRM (USD/COP) y oro (XAU/USD)

**TRM.** Origen oficial: portal de Datos Abiertos de Colombia (plataforma
Socrata), conjunto `32sa-8pi3`, certificado por la Superintendencia Financiera.

Precisión que la v1 pasaba por alto: **la TRM es válida para un rango de
vigencia, no para un día suelto.** El registro trae `vigenciadesde` y
`vigenciahasta`; un valor certificado un viernes rige también sábado y domingo.
La consulta ordena por `vigenciadesde` descendente y la aplicación selecciona la
fila cuyo rango contiene la fecha objetivo, en lugar de asumir correspondencia
uno a uno con el día.

Respaldo: DolarAPI. Se persiste el histórico diario completo en `market_rates`
para alimentar tendencias y conversión patrimonial.

**XAU/USD.** Sondeo cada 20 minutos en horario de mercado, con `bid`, `ask`,
medio y marca de tiempo, más la variación porcentual a 24 h calculada contra la
cotización más próxima a `now() - 24h`. El limitador de frecuencia es explícito
y el respaldo se declara igual que en la TRM —la v1 preveía respaldo para la TRM
pero no para el oro, asimetría que esta versión elimina.

### 7.3 Noticias (RSS/Atom)

Canales: El Tiempo y El Espectador (actualidad); La República y Portafolio
(economía). Se almacenan exclusivamente **titular, extracto, autor, fecha y
enlace de origen**; nunca el cuerpo íntegro del artículo. El sistema es un
agregador que remite al medio, no un espejo de su contenido.

**Deduplicación corregida.** El hash SHA-256 sobre la URL cruda de la v1 falla en
cuanto un medio añade parámetros de campaña: la misma nota entra dos veces. La
v2 calcula el hash sobre una **URL canónica**:

1. Esquema y host en minúsculas; se descarta `www.`.
2. Se eliminan los parámetros de seguimiento (`utm_*`, `fbclid`, `gclid`,
   `mc_cid`, `mc_eid`, `igshid`, `ref`, `s`).
3. Los parámetros restantes se ordenan alfabéticamente.
4. Se elimina el fragmento `#…` y la barra final.

Desempate secundario: índice único sobre `(source_id, title_normalized, published_date)`,
que atrapa las republicaciones con URL nueva.

### 7.4 Resumen matutino

A las 06:00 COT el `worker` toma los cinco titulares económicos más recientes y
solicita a Claude un resumen ejecutivo de tres párrafos, que se persiste en
`news_digests` y se proyecta en el Dashboard. **Una llamada al día**, con la
configuración de [§10](#10-integración-con-claude).

---

## 8. Productividad

### 8.1 Modelo de tareas multidimensional

Una sola fila de `tasks` alimenta tres vistas sin duplicar información:

- **Lista** — orden por `due_date`, `priority`.
- **Matriz de Eisenhower** — derivada de los booleanos `is_urgent` / `is_important`.
  Los cuatro cuadrantes se calculan en la vista; no existe columna "cuadrante"
  que pueda desincronizarse.
- **Kanban** — `status ∈ {todo, in_progress, done}`, más `board_order numeric`
  para permitir reordenar por inserción entre dos vecinos sin reescribir la columna.

**Foco del Día.** No es `due_date::date = current_date`. Es:

```sql
(due_date AT TIME ZONE 'America/Bogota')::date = (now() AT TIME ZONE 'America/Bogota')::date
```

Con `due_date` almacenado en UTC, la forma ingenua desplaza tareas de la noche
al día siguiente. Esta es la clase de error que sólo se manifiesta después de
las 19:00 hora local y desconcierta durante semanas.

### 8.2 Sincronización con Google Calendar

**Saliente (Hub → Google).** Al crear o modificar una tarea con fecha y hora, se
despacha `events.insert` / `events.patch`. El identificador devuelto se guarda en
`tasks.calendar_event_id`.

**Entrante (Google → Hub) — mecanismo primario: sondeo incremental.**
La v1 apostaba por `events.watch`. Ese canal **caduca** y exige renovación
programada; sin ella, la sincronización entrante muere en silencio a las pocas
semanas, y el usuario no lo descubre hasta que confía en un dato erróneo. Para
un sistema de un solo usuario, el sondeo incremental es más simple y
estrictamente más robusto:

- Cada 10 minutos, `events.list` con el `syncToken` guardado.
- Google devuelve **sólo los cambios** desde el token; el coste de cuota es
  despreciable y la latencia máxima de 10 minutos es irrelevante para una agenda
  personal.
- Si Google responde `410 Gone`, el token expiró: se descarta y se ejecuta una
  resincronización completa acotada a ±90 días.

`events.watch` queda documentado como optimización opcional para quien necesite
latencia de segundos, **con la renovación del canal como trabajo programado
obligatorio**. No es el camino por defecto.

**Custodia de credenciales.** El `refresh_token` se cifra con AES-256-GCM según
el contrato de [§4.2](#42-gestión-de-secretos). El `access_token` vive en memoria
del `worker` y se renueva bajo demanda.

**Resolución de conflictos.** Gana la escritura más reciente comparando
`updated_at` local contra `updated` de Google. Todo conflicto se registra en
`job_runs` para que sea auditable.

---

## 9. Finanzas personales

### 9.1 Multimoneda

Cuentas y movimientos en COP, USD y EUR. Dos magnitudes distintas que la v1
confundía en una sola:

| Magnitud | Tasa aplicada | Uso |
|---|---|---|
| **Valor contable** | TRM vigente **en la fecha de la transacción**, congelada en la fila | Histórico, informes, cuadres |
| **Patrimonio consolidado** | TRM **de hoy**, recalculada en cada lectura | "Cuánto tengo ahora mismo" |

Cada `transaction` persiste `fx_rate` y `amount_base` en el momento de su
registro. El patrimonio se calcula al vuelo. Sin esta distinción, el histórico
cambia retroactivamente cada vez que se mueve el dólar.

### 9.2 Ciclo de tarjetas de crédito

`credit_cards` define `closing_day` y `due_day` (día del mes, no fecha fija).
`card_cycles` materializa cada ciclo con sus fechas resueltas y su saldo.

Una compra se asigna al ciclo cuyo rango `[closing_prev+1, closing_current]`
contiene su fecha. La regla de borde —una compra **el mismo día del corte**
pertenece al ciclo que cierra— se fija aquí explícitamente y se prueba.

### 9.3 Diferimiento en cuotas

**Corrección del defecto financiero de la v1.** La fórmula `Cuota = Capital / Plazo`
describe un diferimiento sin intereses. En el mercado colombiano las compras a
cuotas devengan interés corriente casi siempre, de modo que esa fórmula
mostraría al usuario una deuda sistemáticamente **inferior a la real**.

La cuota fija de una anualidad vencida es:

$$\text{Cuota} = P \cdot \frac{i}{1 - (1 + i)^{-n}}$$

donde `P` es el capital, `n` el número de cuotas y `i` la **tasa mensual
efectiva**. Si el usuario introduce una tasa efectiva anual, la conversión es:

$$i = (1 + i_{EA})^{1/12} - 1$$

**Rama de interés cero.** Cuando `i = 0`, la expresión anterior es indeterminada.
El código bifurca explícitamente a `Cuota = P / n`. La v1 no estaba equivocada
en ese caso particular; estaba equivocada al tratarlo como el caso general.

Se genera una tabla de amortización completa por cuota (interés, abono a
capital, saldo), y el redondeo se ajusta en la **última** cuota para que la suma
cuadre exactamente con capital más intereses. Un céntimo descuadrado a doce
cuotas destruye la confianza en todo el módulo.

### 9.4 Presupuestos

Techos mensuales por categoría con seguimiento reactivo y alerta visual al
superar el 80 % y el 100 %. El gasto se agrega por el día local, coherente con
[§8.1](#81-modelo-de-tareas-multidimensional).

---

## 10. Integración con Claude

### 10.1 Selección de modelo

La v1 fijaba Claude 3.5 Sonnet y 3.5 Haiku, ambos descontinuados. Identificadores
vigentes:

| Modelo | ID | Contexto | Entrada $/MTok | Salida $/MTok |
|---|---|---|---|---|
| Claude Opus 5 | `claude-opus-5` | 1M | 5,00 | 25,00 |
| Claude Sonnet 5 | `claude-sonnet-5` | 1M | 2,00 | 10,00 |
| Claude Haiku 4.5 | `claude-haiku-4-5` | 200K | 1,00 | 5,00 |

Los identificadores se usan **exactos, sin sufijo de fecha**. El modelo es
configurable por entorno (`ANTHROPIC_MODEL`, por defecto `claude-opus-5`) para
que el coste sea una decisión del usuario y no una constante enterrada en el
código.

Dos restricciones de esta generación que condicionan el diseño:

- **El prefill del turno `assistant` devuelve error 400.** El arranque en
  personaje se logra por instrucción en `system` o mediante salidas
  estructuradas, nunca prefijando la respuesta.
- `budget_tokens` fue retirado. La profundidad se controla con
  `thinking: {type:"adaptive"}` y `output_config.effort`.

### 10.2 Parámetros por caso de uso

| Caso | Modelo | `effort` | Streaming | Frecuencia |
|---|---|---|---|---|
| Resumen matutino | `ANTHROPIC_MODEL` | `low` | no | 1/día |
| Roleplay | `ANTHROPIC_MODEL` | `low` | **sí** (SSE) | interactivo |
| Compactación de memoria | `claude-haiku-4-5` | — | no | 1 cada ~12 turnos |

Se declaran **fallbacks del lado del servidor** para que un rechazo del
clasificador de seguridad no deje al usuario ante una pantalla vacía.

### 10.3 Memoria y caché de prompts

**El defecto más costoso de la v1.** El documento original inyectaba el bloque de
"Memoria Reciente" *dentro del campo `system`* en cada llamada. El caché de
prompts de Anthropic funciona por **coincidencia de prefijo**: alterar un solo
byte del prefijo invalida todo lo que le sigue. Con esa estrategia, cada resumen
nuevo obliga a pagar íntegros la hoja de personaje y el lore, turno tras turno,
para siempre.

**Arquitectura correcta de la ventana de contexto:**

```
┌─────────────────────────────────────────────────────────┐
│ system  (CONGELADO — cache_control: ephemeral)          │
│   · identidad y persona del personaje                   │
│   · static_lore                                         │
│   · directrices de estilo y restricciones diegéticas    │
│   ← se reutiliza desde caché en cada turno              │
├─────────────────────────────────────────────────────────┤
│ messages[]                                              │
│   · turnos antiguos compactados                         │
│   · {role:"system"} ← MEMORIA RECIENTE, aquí            │
│   · últimos 12 intercambios                             │
│   · turno del usuario                                   │
└─────────────────────────────────────────────────────────┘
```

La memoria viaja como **mensaje `system` intraconversacional dentro del array
`messages`** —soportado en Opus 5 y diseñado exactamente para este fin—, de modo
que el prefijo cacheado permanece intacto. Es además el canal correcto para
instrucciones de operador, resistente a inyección desde el contenido del diálogo.

**Verificación obligatoria.** Se registra `usage.cache_read_input_tokens` en cada
respuesta. Si es cero de forma sostenida, existe un invalidador silencioso
—típicamente una marca de tiempo o un JSON sin orden estable dentro del prefijo—
y debe corregirse antes de considerar el módulo terminado.

**Persistencia.** El resumen de memoria se guarda en `conversation_memories`, no
en memoria de proceso: el contenedor es efímero y una conversación no puede
perder su hilo argumental porque Replit reciclara la instancia.

### 10.4 Aislamiento del módulo de entretenimiento

El roleplay reside bajo `/play`, sin componentes compartidos con el Dashboard ni
notificaciones cruzadas. La separación es de rutas y de navegación, no meramente
visual: proteger la atención durante el trabajo profundo es un requisito
funcional del sistema, no una preferencia estética.

---

## 11. Pasarela de ingesta para agentes

Permite que un agente autónomo deposite informes en el Dashboard sin credenciales
maestras ni inicio de sesión.

### 11.1 Superficie

- `POST /api/v1/agent-gateway/{gatewayId}` — modalidad programática.
- `GET  /agent-submit/{gatewayId}` — formulario web minimalista para captura manual.

Son **dos rutas distintas**. La v1 proponía que un mismo endpoint decidiera su
comportamiento según si accedía "un navegador" —negociación por `User-Agent` o
`Accept`, frágil y fácil de confundir. Separar las rutas elimina la ambigüedad.

### 11.2 Autenticación de la pasarela

**Corrección de seguridad.** La v1 verificaba una contraseña con bcrypt de
factor 12 en cada petición. Bcrypt está diseñado para secretos humanos de baja
entropía y consume del orden de 200–300 ms de CPU por verificación. En un
contenedor pequeño, cualquiera que descubra el `gatewayId` satura el núcleo con
peticiones **no autenticadas**: una denegación de servicio por diseño. El propio
módulo de enlaces compartidos de la v1 ya hacía lo correcto con tokens opacos.

**Esquema v2:**

- Credencial: **token de 32 bytes aleatorios** generado por el servidor y
  mostrado **una única vez** en la interfaz de ajustes.
- Persistencia: **SHA-256** del token. Con 256 bits de entropía, un hash lento
  no aporta nada frente a fuerza bruta y sí abre el vector de DoS.
- Comparación: `crypto.timingSafeEqual` sobre los digests.
- Transporte: `Authorization: Bearer <token>`.
- Rotación: `POST /api/gateways/{id}/rotate`, con revocación inmediata del anterior.

Para el formulario web —donde el secreto sí lo teclea una persona— se admite
adicionalmente una contraseña protegida con **argon2id**. Cada credencial recibe
el tratamiento que le corresponde según su entropía.

### 11.3 Defensas del endpoint

| Control | Implementación |
|---|---|
| Tamaño de payload | Rechazo por `Content-Length` > 64 KiB antes de leer el cuerpo |
| Validación | Esquema Zod estricto; incumplimiento → `422` |
| Saneamiento | El contenido se almacena como texto plano y se escapa al renderizar. Nunca `dangerouslySetInnerHTML` |
| Limitación de frecuencia | 60 peticiones/hora por pasarela, contabilizadas en `gateway_attempts` |
| Bloqueo por fallos | 5 fallos consecutivos → bloqueo de 15 min. Persistido **en base de datos**, no en memoria: el contenedor se reinicia y el atacante no debe recuperar sus intentos |
| Identificación de origen | Primera entrada de `X-Forwarded-For`, almacenada como hash. Detrás del proxy de Replit, `remoteAddress` es siempre el proxy |
| **Idempotencia** | Cabecera `Idempotency-Key` opcional; índice único `(gateway_id, idempotency_key)`. Un reintento devuelve `200` con el registro original en lugar de duplicar el anuncio |

La idempotencia es indispensable: los agentes autónomos reintentan ante timeout,
y sin ella el Dashboard se llena de informes repetidos.

### 11.4 Payload

```json
{
  "category": "market_analysis",
  "title": "Cierre macroeconómico y proyección semanal",
  "content": "La cotización USD/COP cerró al alza…",
  "importance": "high",
  "metadata": { "trm_spot": 4185.20, "xau_trend": "consolidation" },
  "expiresInHours": 24
}
```

`category ∈ {market_analysis, daily_report, alert, reminder, note}`,
`importance ∈ {low, normal, high, critical}`, `title` ≤ 200 caracteres,
`content` ≤ 20 000, `metadata` objeto plano ≤ 4 KiB, `expiresInHours ∈ [1, 720]`.

Tras insertar en `dashboard_announcements`, el endpoint emite `NOTIFY hub_events`
y el Dashboard abierto recibe el informe por SSE sin recargar la página.

---

## 12. Dashboard e interfaces

### 12.1 Distribución

- **Cinta superior (Live Ticker)** — TRM con diferencial, XAU/USD, patrimonio
  consolidado en COP, racha global de hábitos. Cada dato lleva su antigüedad.
- **Zona izquierda** — tres tareas prioritarias del cuadrante urgente/importante,
  próximos eventos de Calendar, hábitos marcables con un toque.
- **Zona central** — último informe del agente externo, seguido de las noticias
  económicas y el resumen matutino.
- **Zona derecha** — estado de la tarjeta principal (días para corte y
  vencimiento, saldo, cupo) y último entrenamiento con sus récords.

### 12.2 Protocolo de doble verificación

Se conserva íntegro el protocolo de la v1, que era una de sus mejores
aportaciones, y se le añade lo que le faltaba: **automatización**.

**Fase A — maquetación y contención**

- `overflow-x: hidden` en la raíz; prohibidos los anchos fijos superiores a 320 px.
- Geometría con unidades relativas, `minmax(0, 1fr)` y flexbox.
- ≥ 1024 px: barra lateral fija. < 1024 px: barra inferior de cuatro accesos
  (Foco, Tareas, Finanzas, Hábitos) más botón flotante de captura rápida;
  herramientas secundarias en menú superior.
- `env(safe-area-inset-*)` en todo elemento anclado a un borde.

**Fase B — interacción y ciclo de vida móvil**

- Área táctil mínima de 44 × 44 px en todo elemento pulsable.
- `100dvh` en contenedores de formulario y `scrollIntoView({block:'center'})`
  al enfocar un campo, para que el teclado virtual no lo oculte.
- `inputmode="decimal"` o `"numeric"` obligatorio en campos de importe y carga.
- El Pomodoro debe sobrevivir al bloqueo de pantalla.

**Automatización (nuevo en v2).** Las fases anteriores eran íntegramente manuales.
Se añade una suite de Playwright que, en cada `push`, recorre las rutas
principales en tres viewports (390×844, 820×1180, 1440×900) y falla la
compilación ante:

- `document.documentElement.scrollWidth > clientWidth` (desbordamiento horizontal).
- Cualquier elemento interactivo con caja de colisión inferior a 44 × 44 px.
- Cualquier campo numérico sin `inputmode`.

Tres comprobaciones triviales de escribir que atrapan la mayoría de las
regresiones móviles antes de llegar a producción.

### 12.3 El Pomodoro y la suspensión del navegador

La v1 proponía ejecutar el temporizador en un Web Worker "para evitar que el
reloj se suspenda". **No funciona:** iOS suspende los Web Workers de pestañas en
segundo plano igual que el hilo principal.

La solución correcta es la que la propia v1 mencionaba a continuación, y que
convierte al Worker en innecesario: **no llevar la cuenta, sino calcularla.**
Se persiste `started_at` absoluto en `study_sessions`; el tiempo restante es
siempre `duration - (Date.now() - started_at)`, recalculado al recuperar el foco
(`visibilitychange`). El temporizador es entonces correcto por construcción,
suspenda el sistema operativo lo que quiera.

### 12.4 Matriz de adaptación

| Interfaz | Ancho | Navegación | Tablas y gráficos | Formularios |
|---|---|---|---|---|
| Escritorio | ≥ 1024 px | Barra lateral persistente, atajos de teclado | SVG completo con tooltips; tablas densas ordenables | Modales centrados, envío con Ctrl/Cmd + Enter |
| Tableta | 768–1023 px | Barra lateral colapsada a iconos o cajón | Muestreo simplificado; desplazamiento horizontal contenido | Dos columnas, controles táctiles ampliados |
| Móvil | < 768 px | Barra inferior de 4 accesos + botón central | Tablas sustituidas por tarjetas apiladas | Hojas inferiores con gesto de arrastre |

---

## 13. Observabilidad y operación

Ausente por completo en la v1. Sin ella, el modo de fallo característico de este
sistema es el peor posible: **datos obsoletos presentados como actuales.**

### 13.1 Registro de trabajos

Cada ejecución del planificador escribe en `job_runs`: nombre, inicio, fin,
estado, filas afectadas, mensaje de error. El panel de ajustes muestra la última
ejecución de cada trabajo con su resultado.

### 13.2 Vigía de obsolescencia

Cada 15 minutos se compara la antigüedad del dato más reciente de cada dominio
contra su umbral:

| Dominio | Umbral | Acción |
|---|---|---|
| TRM | 36 h en día hábil | Aviso en el ticker |
| XAU | 3 h en horario de mercado | Aviso en el ticker |
| Noticias | 6 h | Aviso discreto en la sección |
| Calendar | 45 min | Aviso en la zona de agenda |

El aviso es visible en la interfaz, junto al dato afectado. No se oculta un
fallo de ingesta tras un número plausible.

### 13.3 Respaldos

- Neon conserva historial de puntos en el tiempo según el plan contratado; debe
  verificarse la ventana concreta, no presuponerse.
- Volcado lógico semanal (`pg_dump`) desde el `worker` hacia el almacén de
  objetos, con retención de 8 copias.
- **Prueba de restauración trimestral.** Un respaldo que nunca se ha restaurado
  no es un respaldo; es una suposición.
- El almacén de objetos se configura con versionado si el proveedor lo permite.

### 13.4 Alternativa de despliegues programados

Para quien prefiera no sostener un Reserved VM, cada trabajo del planificador es
invocable por HTTP en `POST /api/jobs/{name}` con un secreto de cabecera
(`CRON_SECRET`). Con ello pueden emplearse Scheduled Deployments de Replit o
cualquier cron externo. Se pierden el bus `LISTEN/NOTIFY` —el SSE degrada a
sondeo— y algo de latencia. La lógica de negocio no cambia en absoluto.

### 13.5 Presupuesto operativo estimado

| Concepto | Estimación mensual (USD) |
|---|---|
| Replit Reserved VM (worker) | 7 – 20 |
| Replit Autoscale (web, uso personal) | 1 – 5 |
| PostgreSQL (Neon, plan de entrada) | 0 – 19 |
| Object Storage (< 20 GB) | 0 – 5 |
| Claude — resumen matutino (1/día, `effort: low`) | < 1 |
| Claude — roleplay | 2 – 15 según uso; el caché de prompts es aquí el factor dominante |
| **Total** | **≈ 10 – 65** |

El rango del roleplay depende casi por completo de que el caché de
[§10.3](#103-memoria-y-caché-de-prompts) funcione. Con el prefijo invalidándose
en cada turno, el extremo superior se multiplica.

---

## 14. Plan de implementación

### Fase 1 — Cimientos
Esquema PostgreSQL y migraciones · autenticación (argon2id + sesiones) ·
Object Storage con URLs presignadas · enlaces compartibles con sus cuatro
políticas · esqueleto del Dashboard · despliegue `web` + `worker` ·
`job_runs` y ruta de salud.

### Fase 2 — Productividad y Rimu
Tareas multidimensionales (lista, Eisenhower, Kanban) · sincronización con
Calendar por sondeo incremental · hábitos con racha flexible y mapa de calor ·
finanzas multimoneda, ciclo de tarjeta y **amortización correcta** ·
entrenamientos con Epley y récords.

### Fase 3 — Mercado e inteligencia
Proveedores de TRM y XAU con respaldo · ingesta RSS con URL canónica ·
resumen matutino con Claude · pasarela de agentes con token opaco e
idempotencia · bus SSE.

### Fase 4 — Entretenimiento y auditoría
Roleplay con hojas de personaje, caché de prompts verificado y streaming ·
compactación de memoria persistida · marcadores con OpenGraph y `tsvector` ·
estudio, Pomodoro y grafo de notas · suite de Playwright de doble verificación.

**Criterio de terminación de cada fase:** migraciones aplicadas, pruebas en
verde, la fase desplegada y observable en `job_runs`. Una fase sin
observabilidad no está terminada.

---

## Apéndice A — Fuentes de datos

| Origen | Uso | Respaldo |
|---|---|---|
| Datos Abiertos Colombia, Socrata `32sa-8pi3` | TRM oficial certificada | DolarAPI |
| API REST de metales al contado | XAU/USD | Segundo proveedor equivalente |
| RSS El Tiempo, El Espectador | Actualidad nacional | — |
| RSS La República, Portafolio | Economía y finanzas | — |
| Google Calendar API v3 | Agenda bidireccional | — |
| Anthropic Messages API | Resúmenes y roleplay | Fallbacks del lado del servidor |

## Apéndice B — Decisiones deliberadamente descartadas

| Descartado | Motivo |
|---|---|
| Redis para el bus de eventos | `LISTEN/NOTIFY` cubre el caso de un usuario sin añadir un servicio más que operar |
| Proveedor externo de identidad | Dependencia y superficie de fallo sin contrapartida para un solo usuario |
| `events.watch` como mecanismo primario | Caduca en silencio; el sondeo incremental es más robusto aquí |
| Web Worker para el Pomodoro | No resuelve la suspensión en iOS; el cálculo por marca de tiempo sí |
| Scraping de medios | Frágil y jurídicamente turbio; RSS es el canal previsto por el editor |
| `float` para importes | Error de redondeo acumulativo inaceptable en un módulo contable |
