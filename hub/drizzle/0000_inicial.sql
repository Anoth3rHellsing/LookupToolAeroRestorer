CREATE TYPE "public"."account_kind" AS ENUM('cash', 'checking', 'savings', 'credit_card', 'investment');--> statement-breakpoint
CREATE TYPE "public"."announcement_category" AS ENUM('market_analysis', 'daily_report', 'alert', 'reminder', 'note');--> statement-breakpoint
CREATE TYPE "public"."announcement_importance" AS ENUM('low', 'normal', 'high', 'critical');--> statement-breakpoint
CREATE TYPE "public"."bookmark_state" AS ENUM('unread', 'reading', 'archived');--> statement-breakpoint
CREATE TYPE "public"."chat_role" AS ENUM('user', 'assistant');--> statement-breakpoint
CREATE TYPE "public"."currency_code" AS ENUM('COP', 'USD', 'EUR');--> statement-breakpoint
CREATE TYPE "public"."file_status" AS ENUM('pending', 'ready');--> statement-breakpoint
CREATE TYPE "public"."habit_log_state" AS ENUM('completed', 'skipped', 'failed');--> statement-breakpoint
CREATE TYPE "public"."job_status" AS ENUM('running', 'succeeded', 'failed');--> statement-breakpoint
CREATE TYPE "public"."news_category" AS ENUM('general', 'economy');--> statement-breakpoint
CREATE TYPE "public"."note_link_kind" AS ENUM('note', 'task', 'habit', 'subject');--> statement-breakpoint
CREATE TYPE "public"."task_status" AS ENUM('todo', 'in_progress', 'done');--> statement-breakpoint
CREATE TYPE "public"."transaction_kind" AS ENUM('income', 'expense', 'transfer');--> statement-breakpoint
CREATE TABLE "oauth_accounts" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"provider" text NOT NULL,
	"provider_account_id" text NOT NULL,
	"refresh_token_encrypted" text NOT NULL,
	"scopes" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"sync_token" text,
	"synced_at" timestamp with time zone,
	"revoked" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sessions" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"token_hash" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"ip_hash" text,
	"user_agent" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY NOT NULL,
	"email" text NOT NULL,
	"password_hash" text NOT NULL,
	"display_name" text NOT NULL,
	"timezone" text DEFAULT 'America/Bogota' NOT NULL,
	"base_currency" text DEFAULT 'COP' NOT NULL,
	"totp_secret" text,
	"storage_quota_bytes" bigint DEFAULT 21474836480 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "events" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"channel" text NOT NULL,
	"payload" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "job_runs" (
	"id" uuid PRIMARY KEY NOT NULL,
	"job_name" text NOT NULL,
	"status" "job_status" NOT NULL,
	"started_at" timestamp with time zone DEFAULT now() NOT NULL,
	"finished_at" timestamp with time zone,
	"rows_affected" integer,
	"error" text,
	"detail" jsonb
);
--> statement-breakpoint
CREATE TABLE "files" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"object_key" text NOT NULL,
	"original_name" text NOT NULL,
	"mime_type" text NOT NULL,
	"size_bytes" bigint NOT NULL,
	"status" "file_status" DEFAULT 'pending' NOT NULL,
	"deleted_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "share_access_log" (
	"id" uuid PRIMARY KEY NOT NULL,
	"shared_link_id" uuid NOT NULL,
	"ip_hash" text,
	"user_agent_hash" text,
	"outcome" text NOT NULL,
	"counted_as_download" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "shared_links" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"file_id" uuid NOT NULL,
	"token_hash" text NOT NULL,
	"password_hash" text,
	"expires_at" timestamp with time zone,
	"max_downloads" integer,
	"download_count" integer DEFAULT 0 NOT NULL,
	"revoked_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tasks" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"title" text NOT NULL,
	"description" text,
	"status" "task_status" DEFAULT 'todo' NOT NULL,
	"is_urgent" boolean DEFAULT false NOT NULL,
	"is_important" boolean DEFAULT false NOT NULL,
	"due_date" timestamp with time zone,
	"board_order" numeric(20, 10) DEFAULT '0' NOT NULL,
	"category" text,
	"tags" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"calendar_event_id" text,
	"completed_at" timestamp with time zone,
	"deleted_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "habit_logs" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"habit_id" uuid NOT NULL,
	"log_date" date NOT NULL,
	"state" "habit_log_state" NOT NULL,
	"note" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "habits" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"name" text NOT NULL,
	"description" text,
	"target_per_week" integer DEFAULT 7 NOT NULL,
	"color" text DEFAULT '#38bdf8' NOT NULL,
	"position" integer DEFAULT 0 NOT NULL,
	"archived_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "exercise_records" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"exercise_slug" text NOT NULL,
	"best_1rm" numeric(20, 4) NOT NULL,
	"best_weight_kg" numeric(20, 4) NOT NULL,
	"achieved_at" timestamp with time zone NOT NULL,
	"set_id" uuid,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "workout_exercises" (
	"id" uuid PRIMARY KEY NOT NULL,
	"workout_id" uuid NOT NULL,
	"exercise_name" text NOT NULL,
	"exercise_slug" text NOT NULL,
	"position" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "workout_sets" (
	"id" uuid PRIMARY KEY NOT NULL,
	"exercise_id" uuid NOT NULL,
	"set_number" integer NOT NULL,
	"weight_kg" numeric(20, 4) NOT NULL,
	"reps" integer NOT NULL,
	"rpe" numeric(20, 4),
	"estimated_1rm" numeric(20, 4),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "workouts" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"performed_at" timestamp with time zone NOT NULL,
	"title" text,
	"notes" text,
	"duration_minutes" integer,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "budgets" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"category" text NOT NULL,
	"month_key" text NOT NULL,
	"amount" numeric(20, 4) NOT NULL,
	"currency" "currency_code" NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "card_cycles" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"card_id" uuid NOT NULL,
	"period_start" date NOT NULL,
	"closing_date" date NOT NULL,
	"due_date" date NOT NULL,
	"billed_amount" numeric(20, 4) DEFAULT '0' NOT NULL,
	"paid_amount" numeric(20, 4) DEFAULT '0' NOT NULL,
	"closed" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "credit_cards" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"account_id" uuid NOT NULL,
	"name" text NOT NULL,
	"closing_day" integer NOT NULL,
	"due_day" integer NOT NULL,
	"credit_limit" numeric(20, 4) NOT NULL,
	"currency" "currency_code" NOT NULL,
	"default_annual_rate" numeric(20, 10),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "financial_accounts" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"name" text NOT NULL,
	"kind" "account_kind" NOT NULL,
	"currency" "currency_code" NOT NULL,
	"opening_balance" numeric(20, 4) DEFAULT '0' NOT NULL,
	"archived_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "installment_items" (
	"id" uuid PRIMARY KEY NOT NULL,
	"plan_id" uuid NOT NULL,
	"number" integer NOT NULL,
	"due_on" date NOT NULL,
	"payment" numeric(20, 4) NOT NULL,
	"interest_portion" numeric(20, 4) NOT NULL,
	"principal_portion" numeric(20, 4) NOT NULL,
	"remaining_balance" numeric(20, 4) NOT NULL,
	"paid_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "installment_plans" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"card_id" uuid NOT NULL,
	"description" text NOT NULL,
	"principal" numeric(20, 4) NOT NULL,
	"currency" "currency_code" NOT NULL,
	"months" integer NOT NULL,
	"monthly_rate" numeric(20, 10) DEFAULT '0' NOT NULL,
	"monthly_payment" numeric(20, 4) NOT NULL,
	"total_interest" numeric(20, 4) NOT NULL,
	"purchased_on" date NOT NULL,
	"settled_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "transactions" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"account_id" uuid NOT NULL,
	"kind" "transaction_kind" NOT NULL,
	"amount" numeric(20, 4) NOT NULL,
	"currency" "currency_code" NOT NULL,
	"fx_rate" numeric(20, 10) DEFAULT '1' NOT NULL,
	"amount_base" numeric(20, 4) NOT NULL,
	"occurred_at" timestamp with time zone NOT NULL,
	"occurred_on" date NOT NULL,
	"category" text,
	"description" text,
	"transfer_peer_id" uuid,
	"card_cycle_id" uuid,
	"installment_item_id" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "study_sessions" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"subject_id" uuid,
	"topic_id" uuid,
	"task_id" uuid,
	"started_at" timestamp with time zone NOT NULL,
	"planned_minutes" integer DEFAULT 25 NOT NULL,
	"ended_at" timestamp with time zone,
	"completed_minutes" integer,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "subjects" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"name" text NOT NULL,
	"color" text DEFAULT '#a78bfa' NOT NULL,
	"archived_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "topics" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"subject_id" uuid NOT NULL,
	"name" text NOT NULL,
	"position" integer DEFAULT 0 NOT NULL,
	"completed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "note_links" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"source_note_id" uuid NOT NULL,
	"kind" "note_link_kind" NOT NULL,
	"target_id" uuid,
	"target_slug" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "notes" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"title" text NOT NULL,
	"body" text DEFAULT '' NOT NULL,
	"slug" text NOT NULL,
	"archived_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "bookmarks" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"url" text NOT NULL,
	"url_canonical" text NOT NULL,
	"url_hash" text NOT NULL,
	"title" text,
	"description" text,
	"image_url" text,
	"site_name" text,
	"state" "bookmark_state" DEFAULT 'unread' NOT NULL,
	"tags" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"read_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "characters" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"slug" text NOT NULL,
	"name" text NOT NULL,
	"persona_prompt" text NOT NULL,
	"static_lore" text DEFAULT '' NOT NULL,
	"avatar_url" text,
	"effort" text DEFAULT 'low' NOT NULL,
	"max_tokens_per_response" integer DEFAULT 1024 NOT NULL,
	"archived_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "chat_messages" (
	"id" uuid PRIMARY KEY NOT NULL,
	"conversation_id" uuid NOT NULL,
	"role" "chat_role" NOT NULL,
	"content" text NOT NULL,
	"position" integer NOT NULL,
	"input_tokens" integer,
	"output_tokens" integer,
	"cache_read_tokens" integer,
	"cache_write_tokens" integer,
	"model" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "conversation_memories" (
	"id" uuid PRIMARY KEY NOT NULL,
	"conversation_id" uuid NOT NULL,
	"summary" text NOT NULL,
	"covers_up_to_position" integer NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "conversations" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"character_id" uuid NOT NULL,
	"title" text,
	"last_message_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "market_commodities" (
	"id" uuid PRIMARY KEY NOT NULL,
	"symbol" text NOT NULL,
	"bid" numeric(20, 4),
	"ask" numeric(20, 4),
	"mid" numeric(20, 4) NOT NULL,
	"source" text NOT NULL,
	"quoted_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "market_rates" (
	"id" uuid PRIMARY KEY NOT NULL,
	"pair" text NOT NULL,
	"value" numeric(20, 4) NOT NULL,
	"valid_from" date NOT NULL,
	"valid_to" date NOT NULL,
	"source" text NOT NULL,
	"fetched_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "news_articles" (
	"id" uuid PRIMARY KEY NOT NULL,
	"source_id" uuid NOT NULL,
	"title" text NOT NULL,
	"title_normalized" text NOT NULL,
	"summary" text,
	"author" text,
	"url" text NOT NULL,
	"url_canonical" text NOT NULL,
	"url_hash" text NOT NULL,
	"published_at" timestamp with time zone NOT NULL,
	"published_on" date NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "news_digests" (
	"id" uuid PRIMARY KEY NOT NULL,
	"digest_date" date NOT NULL,
	"content" text NOT NULL,
	"source_article_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"model" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "news_sources" (
	"id" uuid PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"feed_url" text NOT NULL,
	"site_url" text,
	"category" "news_category" NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"last_fetched_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "agent_gateways" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"name" text NOT NULL,
	"token_hash" text NOT NULL,
	"form_password_hash" text,
	"enabled" boolean DEFAULT true NOT NULL,
	"last_used_at" timestamp with time zone,
	"rotated_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "dashboard_announcements" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"gateway_id" uuid,
	"category" "announcement_category" NOT NULL,
	"title" text NOT NULL,
	"content" text NOT NULL,
	"importance" "announcement_importance" DEFAULT 'normal' NOT NULL,
	"metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"expires_at" timestamp with time zone,
	"read_at" timestamp with time zone,
	"idempotency_key" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "gateway_attempts" (
	"id" uuid PRIMARY KEY NOT NULL,
	"gateway_id" uuid,
	"ip_hash" text,
	"succeeded" boolean NOT NULL,
	"reason" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "oauth_accounts" ADD CONSTRAINT "oauth_accounts_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "sessions" ADD CONSTRAINT "sessions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "events" ADD CONSTRAINT "events_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "files" ADD CONSTRAINT "files_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "share_access_log" ADD CONSTRAINT "share_access_log_shared_link_id_shared_links_id_fk" FOREIGN KEY ("shared_link_id") REFERENCES "public"."shared_links"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "shared_links" ADD CONSTRAINT "shared_links_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "shared_links" ADD CONSTRAINT "shared_links_file_id_files_id_fk" FOREIGN KEY ("file_id") REFERENCES "public"."files"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tasks" ADD CONSTRAINT "tasks_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "habit_logs" ADD CONSTRAINT "habit_logs_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "habit_logs" ADD CONSTRAINT "habit_logs_habit_id_habits_id_fk" FOREIGN KEY ("habit_id") REFERENCES "public"."habits"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "habits" ADD CONSTRAINT "habits_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "exercise_records" ADD CONSTRAINT "exercise_records_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "exercise_records" ADD CONSTRAINT "exercise_records_set_id_workout_sets_id_fk" FOREIGN KEY ("set_id") REFERENCES "public"."workout_sets"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_exercises" ADD CONSTRAINT "workout_exercises_workout_id_workouts_id_fk" FOREIGN KEY ("workout_id") REFERENCES "public"."workouts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_sets" ADD CONSTRAINT "workout_sets_exercise_id_workout_exercises_id_fk" FOREIGN KEY ("exercise_id") REFERENCES "public"."workout_exercises"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workouts" ADD CONSTRAINT "workouts_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "budgets" ADD CONSTRAINT "budgets_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "card_cycles" ADD CONSTRAINT "card_cycles_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "card_cycles" ADD CONSTRAINT "card_cycles_card_id_credit_cards_id_fk" FOREIGN KEY ("card_id") REFERENCES "public"."credit_cards"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "credit_cards" ADD CONSTRAINT "credit_cards_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "credit_cards" ADD CONSTRAINT "credit_cards_account_id_financial_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."financial_accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "financial_accounts" ADD CONSTRAINT "financial_accounts_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "installment_items" ADD CONSTRAINT "installment_items_plan_id_installment_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "public"."installment_plans"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "installment_plans" ADD CONSTRAINT "installment_plans_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "installment_plans" ADD CONSTRAINT "installment_plans_card_id_credit_cards_id_fk" FOREIGN KEY ("card_id") REFERENCES "public"."credit_cards"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_account_id_financial_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."financial_accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "study_sessions" ADD CONSTRAINT "study_sessions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "study_sessions" ADD CONSTRAINT "study_sessions_subject_id_subjects_id_fk" FOREIGN KEY ("subject_id") REFERENCES "public"."subjects"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "study_sessions" ADD CONSTRAINT "study_sessions_topic_id_topics_id_fk" FOREIGN KEY ("topic_id") REFERENCES "public"."topics"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "subjects" ADD CONSTRAINT "subjects_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "topics" ADD CONSTRAINT "topics_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "topics" ADD CONSTRAINT "topics_subject_id_subjects_id_fk" FOREIGN KEY ("subject_id") REFERENCES "public"."subjects"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "note_links" ADD CONSTRAINT "note_links_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "note_links" ADD CONSTRAINT "note_links_source_note_id_notes_id_fk" FOREIGN KEY ("source_note_id") REFERENCES "public"."notes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "notes" ADD CONSTRAINT "notes_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bookmarks" ADD CONSTRAINT "bookmarks_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "characters" ADD CONSTRAINT "characters_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "chat_messages" ADD CONSTRAINT "chat_messages_conversation_id_conversations_id_fk" FOREIGN KEY ("conversation_id") REFERENCES "public"."conversations"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "conversation_memories" ADD CONSTRAINT "conversation_memories_conversation_id_conversations_id_fk" FOREIGN KEY ("conversation_id") REFERENCES "public"."conversations"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_character_id_characters_id_fk" FOREIGN KEY ("character_id") REFERENCES "public"."characters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "news_articles" ADD CONSTRAINT "news_articles_source_id_news_sources_id_fk" FOREIGN KEY ("source_id") REFERENCES "public"."news_sources"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "agent_gateways" ADD CONSTRAINT "agent_gateways_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "dashboard_announcements" ADD CONSTRAINT "dashboard_announcements_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "dashboard_announcements" ADD CONSTRAINT "dashboard_announcements_gateway_id_agent_gateways_id_fk" FOREIGN KEY ("gateway_id") REFERENCES "public"."agent_gateways"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "gateway_attempts" ADD CONSTRAINT "gateway_attempts_gateway_id_agent_gateways_id_fk" FOREIGN KEY ("gateway_id") REFERENCES "public"."agent_gateways"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "oauth_provider_account_key" ON "oauth_accounts" USING btree ("provider","provider_account_id");--> statement-breakpoint
CREATE INDEX "oauth_user_idx" ON "oauth_accounts" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "sessions_token_hash_key" ON "sessions" USING btree ("token_hash");--> statement-breakpoint
CREATE INDEX "sessions_user_idx" ON "sessions" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "sessions_expires_idx" ON "sessions" USING btree ("expires_at");--> statement-breakpoint
CREATE UNIQUE INDEX "users_email_key" ON "users" USING btree ("email");--> statement-breakpoint
CREATE INDEX "events_user_id_idx" ON "events" USING btree ("user_id","id");--> statement-breakpoint
CREATE INDEX "job_runs_name_started_idx" ON "job_runs" USING btree ("job_name","started_at");--> statement-breakpoint
CREATE INDEX "job_runs_status_idx" ON "job_runs" USING btree ("status");--> statement-breakpoint
CREATE UNIQUE INDEX "files_object_key_key" ON "files" USING btree ("object_key");--> statement-breakpoint
CREATE INDEX "files_user_created_idx" ON "files" USING btree ("user_id","created_at");--> statement-breakpoint
CREATE INDEX "files_status_idx" ON "files" USING btree ("status","created_at");--> statement-breakpoint
CREATE INDEX "share_access_link_time_idx" ON "share_access_log" USING btree ("shared_link_id","created_at");--> statement-breakpoint
CREATE INDEX "share_access_dedup_idx" ON "share_access_log" USING btree ("shared_link_id","ip_hash","user_agent_hash","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "shared_links_token_hash_key" ON "shared_links" USING btree ("token_hash");--> statement-breakpoint
CREATE INDEX "shared_links_file_idx" ON "shared_links" USING btree ("file_id");--> statement-breakpoint
CREATE INDEX "shared_links_user_idx" ON "shared_links" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "tasks_user_status_idx" ON "tasks" USING btree ("user_id","status");--> statement-breakpoint
CREATE INDEX "tasks_user_due_idx" ON "tasks" USING btree ("user_id","due_date");--> statement-breakpoint
CREATE INDEX "tasks_user_quadrant_idx" ON "tasks" USING btree ("user_id","is_urgent","is_important");--> statement-breakpoint
CREATE INDEX "tasks_board_idx" ON "tasks" USING btree ("user_id","status","board_order");--> statement-breakpoint
CREATE UNIQUE INDEX "tasks_calendar_event_key" ON "tasks" USING btree ("calendar_event_id");--> statement-breakpoint
CREATE UNIQUE INDEX "habit_logs_habit_date_key" ON "habit_logs" USING btree ("habit_id","log_date");--> statement-breakpoint
CREATE INDEX "habit_logs_user_date_idx" ON "habit_logs" USING btree ("user_id","log_date");--> statement-breakpoint
CREATE INDEX "habits_user_idx" ON "habits" USING btree ("user_id","archived_at");--> statement-breakpoint
CREATE UNIQUE INDEX "exercise_records_user_slug_key" ON "exercise_records" USING btree ("user_id","exercise_slug");--> statement-breakpoint
CREATE INDEX "workout_exercises_workout_idx" ON "workout_exercises" USING btree ("workout_id","position");--> statement-breakpoint
CREATE UNIQUE INDEX "workout_sets_exercise_number_key" ON "workout_sets" USING btree ("exercise_id","set_number");--> statement-breakpoint
CREATE INDEX "workouts_user_performed_idx" ON "workouts" USING btree ("user_id","performed_at");--> statement-breakpoint
CREATE UNIQUE INDEX "budgets_user_category_month_key" ON "budgets" USING btree ("user_id","category","month_key");--> statement-breakpoint
CREATE UNIQUE INDEX "card_cycles_card_closing_key" ON "card_cycles" USING btree ("card_id","closing_date");--> statement-breakpoint
CREATE INDEX "card_cycles_user_due_idx" ON "card_cycles" USING btree ("user_id","due_date");--> statement-breakpoint
CREATE INDEX "credit_cards_user_idx" ON "credit_cards" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "financial_accounts_user_idx" ON "financial_accounts" USING btree ("user_id","archived_at");--> statement-breakpoint
CREATE UNIQUE INDEX "installment_items_plan_number_key" ON "installment_items" USING btree ("plan_id","number");--> statement-breakpoint
CREATE INDEX "installment_items_due_idx" ON "installment_items" USING btree ("due_on","paid_at");--> statement-breakpoint
CREATE INDEX "installment_plans_user_idx" ON "installment_plans" USING btree ("user_id","settled_at");--> statement-breakpoint
CREATE INDEX "transactions_user_date_idx" ON "transactions" USING btree ("user_id","occurred_on");--> statement-breakpoint
CREATE INDEX "transactions_account_date_idx" ON "transactions" USING btree ("account_id","occurred_on");--> statement-breakpoint
CREATE INDEX "transactions_category_idx" ON "transactions" USING btree ("user_id","category","occurred_on");--> statement-breakpoint
CREATE INDEX "transactions_cycle_idx" ON "transactions" USING btree ("card_cycle_id");--> statement-breakpoint
CREATE INDEX "study_sessions_user_started_idx" ON "study_sessions" USING btree ("user_id","started_at");--> statement-breakpoint
CREATE INDEX "study_sessions_open_idx" ON "study_sessions" USING btree ("user_id","ended_at");--> statement-breakpoint
CREATE INDEX "subjects_user_idx" ON "subjects" USING btree ("user_id","archived_at");--> statement-breakpoint
CREATE INDEX "topics_subject_idx" ON "topics" USING btree ("subject_id","position");--> statement-breakpoint
CREATE UNIQUE INDEX "note_links_edge_key" ON "note_links" USING btree ("source_note_id","kind","target_slug");--> statement-breakpoint
CREATE INDEX "note_links_target_idx" ON "note_links" USING btree ("user_id","kind","target_slug");--> statement-breakpoint
CREATE UNIQUE INDEX "notes_user_slug_key" ON "notes" USING btree ("user_id","slug");--> statement-breakpoint
CREATE INDEX "notes_user_updated_idx" ON "notes" USING btree ("user_id","updated_at");--> statement-breakpoint
CREATE UNIQUE INDEX "bookmarks_user_url_hash_key" ON "bookmarks" USING btree ("user_id","url_hash");--> statement-breakpoint
CREATE INDEX "bookmarks_user_state_idx" ON "bookmarks" USING btree ("user_id","state","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "characters_user_slug_key" ON "characters" USING btree ("user_id","slug");--> statement-breakpoint
CREATE UNIQUE INDEX "chat_messages_conv_position_key" ON "chat_messages" USING btree ("conversation_id","position");--> statement-breakpoint
CREATE UNIQUE INDEX "conversation_memories_conv_key" ON "conversation_memories" USING btree ("conversation_id");--> statement-breakpoint
CREATE INDEX "conversations_user_recent_idx" ON "conversations" USING btree ("user_id","last_message_at");--> statement-breakpoint
CREATE INDEX "market_commodities_symbol_time_idx" ON "market_commodities" USING btree ("symbol","quoted_at");--> statement-breakpoint
CREATE UNIQUE INDEX "market_rates_pair_from_key" ON "market_rates" USING btree ("pair","valid_from");--> statement-breakpoint
CREATE INDEX "market_rates_pair_range_idx" ON "market_rates" USING btree ("pair","valid_from","valid_to");--> statement-breakpoint
CREATE UNIQUE INDEX "news_articles_url_hash_key" ON "news_articles" USING btree ("url_hash");--> statement-breakpoint
CREATE UNIQUE INDEX "news_articles_title_dedup_key" ON "news_articles" USING btree ("source_id","title_normalized","published_on");--> statement-breakpoint
CREATE INDEX "news_articles_published_idx" ON "news_articles" USING btree ("published_at");--> statement-breakpoint
CREATE UNIQUE INDEX "news_digests_date_key" ON "news_digests" USING btree ("digest_date");--> statement-breakpoint
CREATE UNIQUE INDEX "news_sources_feed_url_key" ON "news_sources" USING btree ("feed_url");--> statement-breakpoint
CREATE UNIQUE INDEX "agent_gateways_token_hash_key" ON "agent_gateways" USING btree ("token_hash");--> statement-breakpoint
CREATE INDEX "agent_gateways_user_idx" ON "agent_gateways" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "announcements_gateway_idempotency_key" ON "dashboard_announcements" USING btree ("gateway_id","idempotency_key");--> statement-breakpoint
CREATE INDEX "announcements_user_recent_idx" ON "dashboard_announcements" USING btree ("user_id","created_at");--> statement-breakpoint
CREATE INDEX "announcements_expiry_idx" ON "dashboard_announcements" USING btree ("expires_at");--> statement-breakpoint
CREATE INDEX "gateway_attempts_gateway_time_idx" ON "gateway_attempts" USING btree ("gateway_id","created_at");--> statement-breakpoint
CREATE INDEX "gateway_attempts_ip_time_idx" ON "gateway_attempts" USING btree ("ip_hash","created_at");