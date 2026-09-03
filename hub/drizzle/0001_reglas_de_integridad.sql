-- Reglas de integridad, disparadores y vectores de búsqueda.
--
-- Contiene lo que Drizzle no modela de forma nativa y que, sin embargo,
-- es lo que impide que la base de datos acepte estados imposibles. Las
-- restricciones viven aquí y no sólo en la aplicación porque el `worker`,
-- las migraciones y cualquier consola de administración escriben en las
-- mismas tablas: la última línea de defensa tiene que estar en el motor.

-- ---------------------------------------------------------------------
-- 1. Mantenimiento automático de `updated_at`
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'users','sessions','oauth_accounts','files','shared_links','tasks',
    'habits','habit_logs','workouts','financial_accounts','transactions',
    'credit_cards','card_cycles','installment_plans','budgets','subjects',
    'topics','notes','bookmarks','characters','conversations',
    'conversation_memories','news_sources','agent_gateways'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER %I_set_updated_at BEFORE UPDATE ON %I
         FOR EACH ROW EXECUTE FUNCTION set_updated_at()', t, t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 2. Restricciones de verificación
-- ---------------------------------------------------------------------

-- Identidad y almacenamiento
ALTER TABLE "users" ADD CONSTRAINT users_email_format
  CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$');
ALTER TABLE "users" ADD CONSTRAINT users_quota_positive
  CHECK (storage_quota_bytes > 0);
ALTER TABLE "files" ADD CONSTRAINT files_size_non_negative
  CHECK (size_bytes >= 0);

-- Enlaces compartidos: el cupo y el contador no pueden contradecirse.
ALTER TABLE "shared_links" ADD CONSTRAINT shared_links_downloads_sane
  CHECK (download_count >= 0 AND (max_downloads IS NULL OR max_downloads > 0));

-- Tarjetas: días del mes reales.
ALTER TABLE "credit_cards" ADD CONSTRAINT credit_cards_closing_day_range
  CHECK (closing_day BETWEEN 1 AND 31);
ALTER TABLE "credit_cards" ADD CONSTRAINT credit_cards_due_day_range
  CHECK (due_day BETWEEN 1 AND 31);
ALTER TABLE "credit_cards" ADD CONSTRAINT credit_cards_limit_non_negative
  CHECK (credit_limit >= 0);

-- Ciclo de facturación: el periodo debe ser coherente y el vencimiento
-- no puede preceder al corte.
ALTER TABLE "card_cycles" ADD CONSTRAINT card_cycles_period_ordered
  CHECK (period_start <= closing_date AND closing_date <= due_date);

-- Diferimiento en cuotas (ARQUITECTURA.md §9.3).
-- El plazo máximo de 36 meses y la tasa no negativa son condiciones del
-- producto financiero, no preferencias de la interfaz.
ALTER TABLE "installment_plans" ADD CONSTRAINT installment_plans_months_range
  CHECK (months BETWEEN 1 AND 36);
ALTER TABLE "installment_plans" ADD CONSTRAINT installment_plans_principal_positive
  CHECK (principal > 0);
ALTER TABLE "installment_plans" ADD CONSTRAINT installment_plans_rate_non_negative
  CHECK (monthly_rate >= 0);
ALTER TABLE "installment_plans" ADD CONSTRAINT installment_plans_interest_non_negative
  CHECK (total_interest >= 0);
ALTER TABLE "installment_items" ADD CONSTRAINT installment_items_number_positive
  CHECK (number >= 1);
ALTER TABLE "installment_items" ADD CONSTRAINT installment_items_balance_non_negative
  CHECK (remaining_balance >= 0);
-- La descomposición de cada cuota debe cuadrar hasta el último decimal.
ALTER TABLE "installment_items" ADD CONSTRAINT installment_items_payment_decomposition
  CHECK (payment = interest_portion + principal_portion);

-- Entrenamiento: la ecuación de Epley carece de sentido con cargas o
-- repeticiones no positivas, y el RPE es una escala acotada.
ALTER TABLE "workout_sets" ADD CONSTRAINT workout_sets_reps_positive
  CHECK (reps > 0);
ALTER TABLE "workout_sets" ADD CONSTRAINT workout_sets_weight_non_negative
  CHECK (weight_kg >= 0);
ALTER TABLE "workout_sets" ADD CONSTRAINT workout_sets_rpe_range
  CHECK (rpe IS NULL OR rpe BETWEEN 1 AND 10);

-- Hábitos y estudio
ALTER TABLE "habits" ADD CONSTRAINT habits_target_range
  CHECK (target_per_week BETWEEN 1 AND 7);
ALTER TABLE "study_sessions" ADD CONSTRAINT study_sessions_planned_positive
  CHECK (planned_minutes > 0);

-- Vigencia de la TRM: un rango invertido rompería la resolución por fecha.
ALTER TABLE "market_rates" ADD CONSTRAINT market_rates_range_ordered
  CHECK (valid_from <= valid_to);

-- Presupuestos
ALTER TABLE "budgets" ADD CONSTRAINT budgets_amount_positive
  CHECK (amount > 0);
ALTER TABLE "budgets" ADD CONSTRAINT budgets_month_key_format
  CHECK (month_key ~ '^\d{4}-(0[1-9]|1[0-2])$');

-- Anuncios de la pasarela: los límites del payload (§11.4) se aplican
-- también en el motor, no sólo en el esquema Zod del endpoint.
ALTER TABLE "dashboard_announcements" ADD CONSTRAINT announcements_title_length
  CHECK (char_length(title) BETWEEN 1 AND 200);
ALTER TABLE "dashboard_announcements" ADD CONSTRAINT announcements_content_length
  CHECK (char_length(content) BETWEEN 1 AND 20000);

-- ---------------------------------------------------------------------
-- 3. Índices parciales
--
-- Las consultas calientes del Dashboard filtran siempre por «vivo». Un
-- índice parcial es una fracción del tamaño del índice completo y evita
-- que la papelera y el archivo histórico lastren cada lectura.
-- ---------------------------------------------------------------------

CREATE INDEX tasks_active_idx ON "tasks" (user_id, status, board_order)
  WHERE deleted_at IS NULL;

CREATE INDEX tasks_pending_due_idx ON "tasks" (user_id, due_date)
  WHERE deleted_at IS NULL AND status <> 'done';

CREATE INDEX files_live_idx ON "files" (user_id, created_at DESC)
  WHERE deleted_at IS NULL AND status = 'ready';

CREATE INDEX files_orphan_idx ON "files" (created_at)
  WHERE status = 'pending';

CREATE INDEX shared_links_live_idx ON "shared_links" (user_id, created_at DESC)
  WHERE revoked_at IS NULL;

CREATE INDEX installment_items_pending_idx ON "installment_items" (due_on)
  WHERE paid_at IS NULL;

CREATE INDEX announcements_live_idx ON "dashboard_announcements" (user_id, created_at DESC)
  WHERE read_at IS NULL;

-- ---------------------------------------------------------------------
-- 4. Búsqueda de texto completo
--
-- Columnas generadas y no mantenidas por la aplicación: PostgreSQL las
-- recalcula en cada escritura y no pueden desincronizarse del contenido.
-- La configuración 'spanish' aplica lematización y palabras vacías del
-- idioma; usar 'simple' degradaría las consultas a coincidencia literal.
-- ---------------------------------------------------------------------

ALTER TABLE "bookmarks" ADD COLUMN search_vector tsvector
  GENERATED ALWAYS AS (
    setweight(to_tsvector('spanish', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('spanish', coalesce(description, '')), 'B') ||
    setweight(to_tsvector('spanish', coalesce(site_name, '')), 'C')
  ) STORED;

CREATE INDEX bookmarks_search_idx ON "bookmarks" USING GIN (search_vector);

ALTER TABLE "notes" ADD COLUMN search_vector tsvector
  GENERATED ALWAYS AS (
    setweight(to_tsvector('spanish', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('spanish', coalesce(body, '')), 'B')
  ) STORED;

CREATE INDEX notes_search_idx ON "notes" USING GIN (search_vector);

ALTER TABLE "news_articles" ADD COLUMN search_vector tsvector
  GENERATED ALWAYS AS (
    setweight(to_tsvector('spanish', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('spanish', coalesce(summary, '')), 'B')
  ) STORED;

CREATE INDEX news_articles_search_idx ON "news_articles" USING GIN (search_vector);

-- ---------------------------------------------------------------------
-- 5. Notificación del bus de eventos (ARQUITECTURA.md §2.1)
--
-- El disparador emite NOTIFY al insertar en `events`, de modo que el
-- productor no necesita recordar hacerlo. La tabla sigue siendo el
-- registro durable: NOTIFY es efímero y se pierde si no hay escucha, y
-- por eso el consumidor SSE se recupera por cursor sobre `events.id`.
--
-- El payload de NOTIFY se limita al identificador: PostgreSQL impone un
-- máximo de 8000 bytes por notificación, y un anuncio de 20 000
-- caracteres lo desbordaría. El oyente lee la fila por su id.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION notify_hub_event() RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify(
    'hub_events',
    json_build_object('id', NEW.id, 'userId', NEW.user_id, 'channel', NEW.channel)::text
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER events_notify AFTER INSERT ON "events"
  FOR EACH ROW EXECUTE FUNCTION notify_hub_event();
