import { pgEnum } from 'drizzle-orm/pg-core';

/**
 * Dominios cerrados y estables se modelan como enumerados nativos de
 * PostgreSQL. Los dominios que se prevé que crezcan usan `text` con una
 * restricción `check`, más barata de ampliar.
 */

export const currencyCode = pgEnum('currency_code', ['COP', 'USD', 'EUR']);

export const fileStatus = pgEnum('file_status', ['pending', 'ready']);

export const taskStatus = pgEnum('task_status', ['todo', 'in_progress', 'done']);

export const habitLogState = pgEnum('habit_log_state', ['completed', 'skipped', 'failed']);

export const accountKind = pgEnum('account_kind', ['cash', 'checking', 'savings', 'credit_card', 'investment']);

export const transactionKind = pgEnum('transaction_kind', ['income', 'expense', 'transfer']);

export const noteLinkKind = pgEnum('note_link_kind', ['note', 'task', 'habit', 'subject']);

export const bookmarkState = pgEnum('bookmark_state', ['unread', 'reading', 'archived']);

export const chatRole = pgEnum('chat_role', ['user', 'assistant']);

export const newsCategory = pgEnum('news_category', ['general', 'economy']);

export const announcementCategory = pgEnum('announcement_category', [
  'market_analysis',
  'daily_report',
  'alert',
  'reminder',
  'note',
]);

export const announcementImportance = pgEnum('announcement_importance', [
  'low',
  'normal',
  'high',
  'critical',
]);

export const jobStatus = pgEnum('job_status', ['running', 'succeeded', 'failed']);
