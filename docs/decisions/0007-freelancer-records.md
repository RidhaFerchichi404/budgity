# 0007 Freelancer records: clients, projects, invoices, payments

**Status:** accepted

**Context:** Each synced entity costs a table + RLS, a `_sync_x` function, a Drift table, an `EntityType` slot, `ServerRows` mapping, FakeServer support, pgTAP tests and a repository. Payments are recorded by hand, separately from invoices.

**Decision:**
- Four new synced entities, all soft-delete only (like categories) so history keeps its references.
- `clients`: name, email, phone, notes. `projects`: `client_id?`, name, status `active`/`done`, dates.
- `invoices`: `client_id`, `project_id?`, `number?`, status `draft`/`issued`/`paid`/`void` set by the user, `issue_date`, `due_date`, `currency_code`, `items jsonb` (`[{description, quantity_milli, unit_price_minor}]`). The server computes `total_minor` from the items; each line rounds half-up to the minor unit. Overdue is derived: `issued` and past `due_date`.
- `payments`: `client_id`, `project_id?`, `amount_minor`, `currency_code`, `payment_date`, `method`, `note`. No link to invoices or transactions.
- Freelancer income = payments + income transactions in the Freelancer workspace. Received vs. invoiced is compared per client and project, not per invoice. Transactions gain `project_id?` so expenses roll up into project profit.
- Drafts have no number. Issuing assigns `INV-YYYY-NNN` from the local max + 1. The server's `unique (user_id, number)` turns a collision into a conflict the user resolves; this only happens if two devices issue while both are offline.
- Push order becomes profile → category → client → project → invoice → payment → transaction → budget. The `blockedCategoryIds` hold-back in `SyncDao` generalizes to every parent type.

**Consequences:** An invoice and its lines sync and conflict as one unit. Paid status and payments are independent, so a paid invoice with no payment recorded (or the reverse) is possible and is the user's to keep consistent. The same money entered as both a payment and an income transaction counts twice; the payment form says so. Invoices are tracking records, not legal tax invoices: no VAT, fiscal stamp or PDF.
