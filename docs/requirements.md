# Requirements

## Functional (P0, first release)

| ID | Feature | Acceptance criteria |
|---|---|---|
| F1 | Sign up / in / out | Email + password via Supabase Auth. Sign-out tries a final sync, warns about pending changes, then purges local data. |
| F2 | Local DB init | SQLite is created and migrated on first launch, and upgrades keep existing data. |
| F3 | Transactions | Create, view, edit, and delete income and expenses with no network. |
| F4 | Categories | Income/expense categories with icons. Archiving keeps history intact. |
| F5 | Dashboard | Balance, this month's income and expenses, budget progress, and recent transactions update immediately. |
| F6 | Budgets | Limit per period (optionally per category), showing spent vs. limit. |
| F7 | Automatic sync | Changes eventually reach Supabase and the other device. |
| F8 | Conflicts | Concurrent edits are detected and resolved by the user, never lost silently. |
| F9 | Sync status | Shows online/offline, pending count, last sync, failed ops, and conflicts. |
| F10 | Platforms | All of the above works offline on Windows and Android. |

## Functional (v2)

| ID | Feature | Acceptance criteria |
|---|---|---|
| F11 | Workspaces | One account has Personal and, once enabled, Freelancer. Switching needs no sign-out. Data, totals and categories never mix. |
| F12 | Clients and projects | Create, edit and archive offline. Archived ones keep their history. |
| F13 | Invoices | Draft, issue (assigns a number), mark paid, void. Line items with quantity and unit price. Total computed, never typed. Overdue shown when issued and past due. |
| F14 | Payments | Entered manually with client, optional project, amount, date, method, note. Not linked to invoices or transactions. |
| F15 | Freelancer analytics | Invoiced vs. received per client and project, overdue invoices, income (payments + income transactions) and expenses, profit per project. |
| F16 | Personal analytics | Month-over-month, spending by category, income vs. expense over time, budget health. Grouped by currency. |
| F17 | Insights and suggestions | Rule-based observations (category up X% vs. last month, budget at 85%, overdue invoices). Category suggested from past descriptions. Offline. |
| F18 | Ask Budgity | Natural-language questions answered from computed figures only. Shows the figures it used. Needs network; nothing else does. |

P1 (later): savings goals, CSV export, analytics/charts, recurring transactions, currency conversion,
local DB encryption.

## Non-functional

- **Correctness of money:** integer minor units only. Never add amounts in different currencies.
- **Durability:** a saved transaction is never lost by a crash, restart, network failure, or retry.
- **Security:** RLS on every user-owned table. Only the publishable key ships in the client.
  Tokens live in OS secure storage.
- **Responsiveness:** UI reads are local, and no screen waits on the network.
- **Portability:** one codebase. Layout adapts at 840 px width.
