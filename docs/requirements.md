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

P1 (later): savings goals, CSV export, analytics/charts, recurring transactions, currency conversion,
local DB encryption.

## Non-functional

- **Correctness of money:** integer minor units only. Never add amounts in different currencies.
- **Durability:** a saved transaction is never lost by a crash, restart, network failure, or retry.
- **Security:** RLS on every user-owned table. Only the publishable key ships in the client.
  Tokens live in OS secure storage.
- **Responsiveness:** UI reads are local, and no screen waits on the network.
- **Portability:** one codebase. Layout adapts at 840 px width.
