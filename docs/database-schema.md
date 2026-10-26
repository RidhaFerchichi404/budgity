# Database schema

The same core model exists in PostgreSQL and in each device's SQLite. Authoritative definitions:
`supabase/migrations/` (cloud) and `lib/database/tables/` (local).

## Shared entities

All synced tables have `id uuid` (generated on the client), `user_id`, `created_at`, `updated_at`,
`deleted_at` (soft delete), `version int` (optimistic concurrency), and `change_seq bigint`
(server-assigned pull cursor).

| Table | Fields |
|---|---|
| `profiles` | `id` (= auth user id), `display_name`, `currency_code`, `created_at`, `updated_at`, `change_seq` |
| `categories` | `name`, `type` (`income`/`expense`), `icon_key`, `sort_order` |
| `transactions` | `category_id?`, `type`, `amount_minor > 0`, `currency_code`, `description`, `transaction_date` |
| `budgets` | `category_id?`, `name`, `amount_minor > 0`, `currency_code`, `period_start`, `period_end >= period_start` |

### Constraints

- `type in ('income','expense')`. `currency_code` is 3 uppercase letters.
- Composite FK `(category_id, user_id) → categories(id, user_id)`, so a row can only reference its owner's category.
- Categories are never hard-deleted (soft delete only), so history keeps its category.
- Indexes: `(user_id, change_seq)` on every synced table, `(user_id, transaction_date)` on transactions.

## Money

Amounts are integers in the currency's minor unit. Exponents: TND 3, EUR 2, USD 2 (see `lib/core/money`).
Totals are always grouped by currency.

## Server-only

- `sync_operations(op_id pk, user_id, result jsonb, created_at)`: idempotency ledger. RLS on, no policies.
- `change_seq_global` sequence, assigned by trigger on insert and update.

## Local-only

| Table | Purpose |
|---|---|
| `sync_queue` | Pending ops: `id` (op uuid), `entity_type`, `entity_id`, `operation`, `payload`, `base_version`, `created_at`, `attempt_count`, `next_attempt_at`, `status`, `last_error` |
| `sync_metadata` | key/value: per-table pull cursors, last sync time, background lease |
| `sync_conflicts` | Local payload vs. server row for unresolved conflicts |

Drift tracks the schema version through `PRAGMA user_version`, and snapshots live in `drift_schemas/`.
