# Esquema de datos — Hub Personal

Referencia del modelo relacional. Complementa `ARQUITECTURA.md`; las
referencias `§n` remiten a ese documento.

**Implementación:** `src/db/schema/*.ts` (Drizzle ORM).
**Migraciones:** `drizzle/`.

| Métrica | Valor |
|---|---|
| Tablas | 40 |
| Índices | 120 |
| Claves foráneas | 47 |
| Restricciones de verificación | 25 |
| Disparadores | 25 |

> **Estado de verificación.** Las tres migraciones se han aplicado sobre
> PostgreSQL 16.13 y se ha comprobado, con inserciones reales, que cada
> restricción rechaza lo que debe rechazar, que el disparador de eventos
> emite por `pg_notify`, que las columnas `tsvector` lematizan en español
> y que `updated_at` avanza solo.

---

## 1. Convenciones

### 1.1 Claves primarias — UUID v7 en dos niveles

La aplicación genera el identificador con Drizzle (`$defaultFn`), lo que
evita una ida y vuelta a la base de datos. **Adicionalmente**, cada columna
lleva `DEFAULT uuid_generate_v7()` en el motor.

Ambos niveles son necesarios, y descubrirlo costó una prueba: `$defaultFn`
es puramente de la aplicación y **no emite un `DEFAULT` en el SQL**, de
modo que cualquier inserción que no pase por Drizzle —una consola de
administración, un script de siembra, un trabajo en SQL crudo del
`worker`— fallaba con `null value in column "id"`. La función
`uuid_generate_v7()` de la migración `0002` es la red de seguridad.

Se implementa v7 y no `gen_random_uuid()` (que es v4) para conservar la
propiedad que motivó la elección: el **orden temporal**, y con él la
localidad de índice en inserciones secuenciales.

### 1.2 Tiempo

| Tipo | Uso |
|---|---|
| `timestamptz` | Todo instante. Siempre UTC en reposo |
| `date` | Fecha civil ya resuelta en la zona del usuario |

Las columnas `date` (`habit_logs.log_date`, `transactions.occurred_on`,
`news_articles.published_on`, todas las de ciclo y cuota) **no son
redundantes**: son la conversión de zona hecha una sola vez, al escribir.
Sin ellas, cada agregación mensual arrastraría `AT TIME ZONE` sobre toda
la tabla y no podría usar un índice.

La frontera de día se resuelve siempre así:

```sql
(due_date AT TIME ZONE 'America/Bogota')::date
  = (now() AT TIME ZONE 'America/Bogota')::date
```

Comprobación que justifica la regla: `2026-09-04 01:30 UTC` es el **3** de
septiembre en Bogotá. La comparación ingenua contra `current_date` lo
situaría en el 4, desplazando al día siguiente toda tarea posterior a las
19:00 locales.

### 1.3 Dinero

`numeric(20,4)` mediante el ayudante `money()`; tasas con
`numeric(20,10)` mediante `rate()`. **Jamás coma flotante.** Drizzle
devuelve `string`, que es justo lo que necesita `decimal.js` para operar
sin pérdida. Cuatro decimales cubren la aritmética de intereses; el
redondeo a la unidad mínima de la divisa ocurre en presentación.

### 1.4 Tenencia

Toda tabla de negocio lleva
`user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE`
mediante el ayudante `userRef()`.

**Excepciones deliberadas:**

| Tabla | Motivo |
|---|---|
| `market_rates`, `market_commodities` | Dato de mercado, no del usuario |
| `news_sources`, `news_articles`, `news_digests` | Corpus compartido |
| `job_runs` | Infraestructura del proceso; debe sobrevivir al borrado de un usuario para poder auditarse |

Las tablas hijas (`workout_sets`, `installment_items`, `chat_messages`…)
heredan la tenencia por su padre y no repiten la columna.

---

## 2. Dominios

### 2.1 Identidad

| Tabla | Función |
|---|---|
| `users` | Cuenta, zona horaria, divisa base, cuota de almacenamiento |
| `sessions` | SHA-256 del token de cookie, caducidad, huella de origen |
| `oauth_accounts` | Credencial de Google cifrada + `sync_token` de Calendar |

`users.password_hash` es **argon2id**: secreto humano de baja entropía,
hash deliberadamente lento. `sessions.token_hash` es **SHA-256**: 32 bytes
aleatorios no necesitan más, y un hash lento en cada petición
autenticada sería un impuesto permanente.

`oauth_accounts.refresh_token_encrypted` guarda
`v1.<nonce>.<ciphertext>.<authTag>` (§4.2). El nonce es de 12 bytes,
**único por operación**: reutilizarlo con la misma clave rompe AES-GCM por
completo. El prefijo de versión permite rotar clave o algoritmo sin
ambigüedad.

### 2.2 Archivos

| Tabla | Función |
|---|---|
| `files` | Metadatos y `object_key`; estado `pending` → `ready` |
| `shared_links` | Token, contraseña, caducidad, cupo de descargas |
| `share_access_log` | Auditoría y desduplicación del contador |

El ciclo `pending`/`ready` es lo que impide que exista una fila que
promete un archivo inexistente: sólo `commit` la promueve, y sólo tras un
`HEAD` contra el almacén. El índice parcial `files_orphan_idx` alimenta el
barrido horario que recoge las cargas abandonadas.

`share_access_log.counted_as_download` resuelve la ambigüedad de la v1
(§6.4): los navegadores emiten peticiones por rangos y reintentan, de modo
que contar peticiones revocaría enlaces legítimos.

### 2.3 Productividad

`tasks` alimenta lista, matriz de Eisenhower y Kanban desde una sola fila.

- **No existe columna «cuadrante»**: se deriva de `is_urgent` /
  `is_important` en la consulta, de modo que no puede desincronizarse.
- `board_order` es `numeric(20,10)` y no `integer`: reordenar por arrastre
  calcula el punto medio entre dos vecinos y escribe **una** fila, en
  lugar de reescribir la columna entera.
- `calendar_event_id` lleva índice único. PostgreSQL admite múltiples
  `NULL` en un índice único, de modo que las tareas sin evento espejo no
  colisionan entre sí.

### 2.4 Hábitos

`habit_logs.state ∈ {completed, skipped, failed}`. El estado `skipped` es
lo que distingue este motor de rachas de un contador binario: **congela**
la racha acumulada sin restablecerla a cero.

`log_date` es `date` porque un hábito pertenece a un día civil, no a un
instante. El único `(habit_id, log_date)` impide el doble registro.

### 2.5 Entrenamiento

`exercise_slug` normaliza «Press banca», «press de banca» y «Press Banca»
a un mismo movimiento. Sin él, los récords personales se fragmentan por la
ortografía.

`workout_sets.estimated_1rm` se **persiste** en lugar de recalcularse, para
que un cambio futuro de fórmula no reescriba el histórico de récords.

`exercise_records` es tabla propia y no una bandera `is_pr` sobre la
serie: consultar «mi mejor press banca» debe ser una lectura por índice,
no un barrido del histórico.

### 2.6 Finanzas

**La distinción que la v1 no hacía:**

| Magnitud | Origen | Cuándo se calcula |
|---|---|---|
| Valor contable | `transactions.fx_rate` y `amount_base`, **congelados** | Al registrar |
| Patrimonio consolidado | TRM de hoy sobre saldos vivos | En cada lectura |

Sin esta separación, cada movimiento del dólar reescribiría
retroactivamente todo el histórico del usuario.

**Cuotas (§9.3).** `installment_plans.monthly_rate` es la tasa mensual
efectiva ya convertida desde la E.A., persistida junto al plan porque es
un término del contrato: corregir la tasa más adelante no debe mutar un
plan vigente bajo los pies del usuario.

La restricción `installment_items_payment_decomposition` obliga a que
`payment = interest_portion + principal_portion` **en cada fila**. Es la
garantía, verificada por el motor, de que la tabla de amortización cuadra.

**Regla de borde del ciclo**, fijada y probada: una compra realizada el
mismo día del corte pertenece al ciclo que cierra ese día; `period_start`
es el día siguiente al corte anterior.

### 2.7 Estudio y conocimiento

`study_sessions.started_at` absoluto es **todo** el mecanismo del Pomodoro
(§12.3): el tiempo restante se calcula, nunca se lleva en un contador que
el navegador pueda suspender.

`notes.slug` es el título normalizado —minúsculas, sin acentos ni espacios
redundantes— y es la clave por la que se resuelve `[[Enlace]]`. Sin él,
«Cálculo» y «calculo» serían dos nodos distintos del grafo.

`note_links` admite `target_id` nulo con `target_slug` poblado: es un
**nodo fantasma**, un enlace a una nota que aún no existe. El grafo lo
dibuja en trazo tenue y se resuelve solo en cuanto la nota se cree.

### 2.8 Entretenimiento

`characters` compone el bloque `system` **congelado** de la llamada a
Claude. Todo lo que aquí vive es prefijo estable y por tanto cacheable;
nada volátil puede entrar.

> **Corrección respecto a la v1.** La hoja de personaje original incluía
> `"temperature": 0.85`. Los parámetros de muestreo (`temperature`,
> `top_p`, `top_k`) fueron **retirados** en esta generación de modelos y
> devuelven error 400. El control equivalente es `output_config.effort`,
> que es lo que persiste la columna `effort`.

`conversation_memories` guarda el resumen compactado **en la base de
datos**, no en memoria de proceso: el contenedor es efímero y una
conversación no puede perder su hilo argumental porque Replit reciclara la
instancia. `covers_up_to_position` hace la compactación incremental.

`chat_messages` registra `cache_read_tokens`. **Si es cero de forma
sostenida, hay un invalidador silencioso en el prefijo y el módulo no está
terminado**, por bien que responda.

### 2.9 Mercados

`market_rates` modela `valid_from` / `valid_to` y no una fecha suelta,
porque **la TRM es válida para un rango de vigencia**: el valor
certificado un viernes rige también sábado y domingo. Verificado:
consultar el 2026-09-06 devuelve la TRM cuya vigencia va del 4 al 6.

`source` en ambas tablas registra el proveedor efectivo, de modo que sea
auditable cuándo se sirvió el respaldo en lugar del origen primario.

### 2.10 Noticias

Desduplicación en **dos** niveles, corrigiendo la v1:

1. `url_hash` — SHA-256 sobre la URL **canónica**. El hash sobre la URL
   cruda falla en cuanto un medio añade parámetros de campaña.
2. `(source_id, title_normalized, published_on)` — atrapa la
   republicación con URL nueva, que el hash por sí solo deja pasar.

Se almacena exclusivamente titular, extracto, autor, fecha y enlace: el
sistema remite al medio, no lo replica.

### 2.11 Pasarela de agentes

| Credencial | Hash | Motivo |
|---|---|---|
| `agent_gateways.token_hash` | SHA-256 | 32 bytes aleatorios; un hash lento sólo abriría un vector de DoS |
| `agent_gateways.form_password_hash` | argon2id | Lo teclea una persona |

`gateway_attempts` vive en la base de datos y no en memoria por una razón
concreta: el contenedor se reinicia, y un atacante no debe recuperar sus
intentos fallidos con sólo esperar a que Replit recicle la instancia.

`dashboard_announcements.idempotency_key` con índice único sobre
`(gateway_id, idempotency_key)` es indispensable: los agentes autónomos
reintentan ante timeout, y sin él el Dashboard se llena de duplicados.

### 2.12 Operación

`events` usa `bigserial` deliberadamente: hace falta un **cursor
monótono**, no un identificador aleatorio. `NOTIFY` es efímero y se pierde
si no hay escucha; la tabla es el registro durable que permite al
consumidor SSE recuperar por cursor lo ocurrido durante una desconexión.

El disparador `events_notify` emite sólo el identificador. PostgreSQL
impone un máximo de 8000 bytes por notificación, y un anuncio de 20 000
caracteres lo desbordaría; el oyente lee la fila por su `id`.

---

## 3. Restricciones de verificación

Viven en el motor y no sólo en la aplicación porque el `worker`, las
migraciones y cualquier consola de administración escriben en las mismas
tablas: la última línea de defensa tiene que estar en la base de datos.

| Restricción | Invariante |
|---|---|
| `users_email_format` | Forma de dirección de correo |
| `users_quota_positive` | Cuota > 0 |
| `files_size_non_negative` | Tamaño ≥ 0 |
| `shared_links_downloads_sane` | Contador ≥ 0; cupo nulo o > 0 |
| `credit_cards_closing_day_range` / `_due_day_range` | Día del mes en 1–31 |
| `credit_cards_limit_non_negative` | Cupo ≥ 0 |
| `card_cycles_period_ordered` | `inicio ≤ corte ≤ vencimiento` |
| `installment_plans_months_range` | Plazo en 1–36 |
| `installment_plans_principal_positive` | Capital > 0 |
| `installment_plans_rate_non_negative` | Tasa ≥ 0 |
| `installment_plans_interest_non_negative` | Interés total ≥ 0 |
| `installment_items_payment_decomposition` | `pago = interés + capital` |
| `installment_items_balance_non_negative` | Saldo ≥ 0 |
| `installment_items_number_positive` | Número de cuota ≥ 1 |
| `workout_sets_reps_positive` | Repeticiones > 0 |
| `workout_sets_weight_non_negative` | Carga ≥ 0 |
| `workout_sets_rpe_range` | RPE en 1–10 |
| `habits_target_range` | Objetivo semanal en 1–7 |
| `study_sessions_planned_positive` | Minutos > 0 |
| `market_rates_range_ordered` | `valid_from ≤ valid_to` |
| `budgets_amount_positive` | Importe > 0 |
| `budgets_month_key_format` | `YYYY-MM` con mes en 01–12 |
| `announcements_title_length` | 1–200 caracteres |
| `announcements_content_length` | 1–20 000 caracteres |

---

## 4. Índices

### 4.1 Parciales

Las consultas calientes del Dashboard filtran siempre por «vivo». Un
índice parcial es una fracción del tamaño del completo y evita que la
papelera y el archivo histórico lastren cada lectura.

| Índice | Predicado |
|---|---|
| `tasks_active_idx` | `deleted_at IS NULL` |
| `tasks_pending_due_idx` | `deleted_at IS NULL AND status <> 'done'` |
| `files_live_idx` | `deleted_at IS NULL AND status = 'ready'` |
| `files_orphan_idx` | `status = 'pending'` (alimenta el barrido) |
| `shared_links_live_idx` | `revoked_at IS NULL` |
| `installment_items_pending_idx` | `paid_at IS NULL` |
| `announcements_live_idx` | `read_at IS NULL` |

### 4.2 Búsqueda de texto completo

Columnas `search_vector` **generadas** (`GENERATED ALWAYS AS … STORED`)
con índice GIN en `bookmarks`, `notes` y `news_articles`. PostgreSQL las
recalcula en cada escritura, de modo que no pueden desincronizarse del
contenido —a diferencia de un vector mantenido desde la aplicación.

Configuración `'spanish'`, con pesos `A` para el título, `B` para el
cuerpo y `C` para el sitio. Usar `'simple'` degradaría las consultas a
coincidencia literal. Verificado: buscar `invertir` recupera
«**Inversiones** en renta variable» por lematización.

---

## 5. Migraciones

| Archivo | Contenido |
|---|---|
| `0000_inicial.sql` | 40 tablas, 70 índices, 47 claves foráneas, enumerados |
| `0001_reglas_de_integridad.sql` | Disparadores `updated_at`, 25 restricciones, índices parciales, `tsvector` + GIN, disparador `NOTIFY` |
| `0002_uuid_v7_por_defecto.sql` | `uuid_generate_v7()` y su aplicación a toda clave primaria |

```bash
npm run db:generate   # deriva SQL del esquema TypeScript
npm run db:migrate    # aplica lo pendiente
```

La `0002` recorre el catálogo del sistema en lugar de enumerar cuarenta
tablas a mano: una tabla futura que olvide su `DEFAULT` queda cubierta con
sólo reejecutarla.
