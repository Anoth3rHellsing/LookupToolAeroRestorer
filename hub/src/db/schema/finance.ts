import { boolean, date, index, integer, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';
import { accountKind, currencyCode, transactionKind } from './enums';
import { userRef } from './identity';
import { createdAt, money, pk, rate, updatedAt } from './_shared';

export const financialAccounts = pgTable('financial_accounts', {
  id: pk(),
  userId: userRef(),
  name: text('name').notNull(),
  kind: accountKind('kind').notNull(),
  currency: currencyCode('currency').notNull(),
  openingBalance: money('opening_balance').notNull().default('0'),
  archivedAt: timestamp('archived_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [index('financial_accounts_user_idx').on(t.userId, t.archivedAt)]);

/**
 * Movimientos (ARQUITECTURA.md §9.1).
 *
 * Aquí vive la distinción que la v1 no hacía, y que decide si el
 * histórico es estable o cambia solo:
 *
 *   · `fxRate` y `amountBase` se CONGELAN en el momento del registro.
 *     Son el valor contable: lo que costó, cuando costó.
 *   · El patrimonio consolidado NO se lee de aquí. Se recalcula al vuelo
 *     con la TRM de hoy sobre los saldos vivos.
 *
 * Sin esta separación, cada movimiento del dólar reescribiría
 * retroactivamente todo el histórico del usuario.
 *
 * `occurredOn` es la fecha civil local del movimiento, derivada al
 * escribir. Existe para que los cortes de presupuesto y de ciclo de
 * tarjeta no arrastren conversiones de zona horaria en cada consulta.
 */
export const transactions = pgTable('transactions', {
  id: pk(),
  userId: userRef(),
  accountId: uuid('account_id').notNull().references(() => financialAccounts.id, { onDelete: 'cascade' }),
  kind: transactionKind('kind').notNull(),
  amount: money('amount').notNull(),
  currency: currencyCode('currency').notNull(),
  fxRate: rate('fx_rate').notNull().default('1'),
  amountBase: money('amount_base').notNull(),
  occurredAt: timestamp('occurred_at', { withTimezone: true }).notNull(),
  occurredOn: date('occurred_on', { mode: 'string' }).notNull(),
  category: text('category'),
  description: text('description'),
  transferPeerId: uuid('transfer_peer_id'),
  cardCycleId: uuid('card_cycle_id'),
  installmentItemId: uuid('installment_item_id'),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [
  index('transactions_user_date_idx').on(t.userId, t.occurredOn),
  index('transactions_account_date_idx').on(t.accountId, t.occurredOn),
  index('transactions_category_idx').on(t.userId, t.category, t.occurredOn),
  index('transactions_cycle_idx').on(t.cardCycleId),
]);

/**
 * Tarjetas de crédito (§9.2).
 *
 * `closingDay` y `dueDay` son días del mes, no fechas: el ciclo se
 * resuelve mes a mes en `cardCycles`, contemplando los meses que no
 * tienen día 31.
 */
export const creditCards = pgTable('credit_cards', {
  id: pk(),
  userId: userRef(),
  accountId: uuid('account_id').notNull().references(() => financialAccounts.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  closingDay: integer('closing_day').notNull(),
  dueDay: integer('due_day').notNull(),
  creditLimit: money('credit_limit').notNull(),
  currency: currencyCode('currency').notNull(),
  /** Tasa efectiva anual por defecto para nuevos diferimientos. */
  defaultAnnualRate: rate('default_annual_rate'),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [index('credit_cards_user_idx').on(t.userId)]);

/**
 * Ciclo de facturación materializado.
 *
 * Regla de borde, fijada aquí y probada: una compra realizada EL MISMO
 * DÍA del corte pertenece al ciclo que cierra ese día. `periodStart` es
 * por tanto el día siguiente al corte anterior.
 */
export const cardCycles = pgTable('card_cycles', {
  id: pk(),
  userId: userRef(),
  cardId: uuid('card_id').notNull().references(() => creditCards.id, { onDelete: 'cascade' }),
  periodStart: date('period_start', { mode: 'string' }).notNull(),
  closingDate: date('closing_date', { mode: 'string' }).notNull(),
  dueDate: date('due_date', { mode: 'string' }).notNull(),
  billedAmount: money('billed_amount').notNull().default('0'),
  paidAmount: money('paid_amount').notNull().default('0'),
  closed: boolean('closed').notNull().default(false),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [
  uniqueIndex('card_cycles_card_closing_key').on(t.cardId, t.closingDate),
  index('card_cycles_user_due_idx').on(t.userId, t.dueDate),
]);

/**
 * Plan de diferimiento en cuotas (§9.3).
 *
 * CORRECCIÓN CENTRAL respecto a la v1. Aquella calculaba
 * `Cuota = Capital / Plazo`, que describe un diferimiento SIN intereses.
 * En el mercado colombiano las compras a cuotas devengan interés
 * corriente casi siempre, de modo que esa fórmula mostraba al usuario una
 * deuda sistemáticamente inferior a la real.
 *
 * `monthlyRate` es la tasa mensual efectiva ya convertida desde la E.A.
 * Se persiste junto al plan porque es un término del contrato: si el
 * usuario corrige la tasa más adelante, el plan vigente no debe mutar
 * bajo sus pies.
 *
 * `monthlyPayment`, `totalInterest` y la tabla de amortización completa
 * se calculan una vez, al crear el plan, y se congelan. Recalcular en
 * cada lectura invita a que un cambio de redondeo desplace céntimos en
 * un histórico ya conciliado.
 */
export const installmentPlans = pgTable('installment_plans', {
  id: pk(),
  userId: userRef(),
  cardId: uuid('card_id').notNull().references(() => creditCards.id, { onDelete: 'cascade' }),
  description: text('description').notNull(),
  principal: money('principal').notNull(),
  currency: currencyCode('currency').notNull(),
  months: integer('months').notNull(),
  monthlyRate: rate('monthly_rate').notNull().default('0'),
  monthlyPayment: money('monthly_payment').notNull(),
  totalInterest: money('total_interest').notNull(),
  purchasedOn: date('purchased_on', { mode: 'string' }).notNull(),
  settledAt: timestamp('settled_at', { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [index('installment_plans_user_idx').on(t.userId, t.settledAt)]);

/**
 * Cuota individual del plan.
 *
 * El descuadre de redondeo se absorbe íntegramente en la ÚLTIMA cuota,
 * de modo que la suma de `principalPortion` iguale exactamente al capital
 * y `remainingBalance` termine en cero. Un céntimo descuadrado a doce
 * cuotas destruye la confianza en todo el módulo contable.
 */
export const installmentItems = pgTable('installment_items', {
  id: pk(),
  planId: uuid('plan_id').notNull().references(() => installmentPlans.id, { onDelete: 'cascade' }),
  number: integer('number').notNull(),
  dueOn: date('due_on', { mode: 'string' }).notNull(),
  payment: money('payment').notNull(),
  interestPortion: money('interest_portion').notNull(),
  principalPortion: money('principal_portion').notNull(),
  remainingBalance: money('remaining_balance').notNull(),
  paidAt: timestamp('paid_at', { withTimezone: true }),
}, (t) => [
  uniqueIndex('installment_items_plan_number_key').on(t.planId, t.number),
  index('installment_items_due_idx').on(t.dueOn, t.paidAt),
]);

/** Techos mensuales por categoría. `monthKey` en formato `YYYY-MM` local. */
export const budgets = pgTable('budgets', {
  id: pk(),
  userId: userRef(),
  category: text('category').notNull(),
  monthKey: text('month_key').notNull(),
  amount: money('amount').notNull(),
  currency: currencyCode('currency').notNull(),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [uniqueIndex('budgets_user_category_month_key').on(t.userId, t.category, t.monthKey)]);
