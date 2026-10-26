# Development roadmap

Each phase ends with a gate. Don't start the next phase until the gate passes.

| # | Phase | Gate |
|---|---|---|
| 0 | Repo, docs, ADRs, Flutter scaffold | `flutter analyze` clean, app runs on Windows |
| 1 | Supabase schema, RLS, `sync_push`, signup trigger, pgTAP | `supabase test db` green, advisors clean |
| 2 | Drift schema, sync tables, migrations | DAO and migration tests green |
| 3 | **Walking skeleton:** auth, money, transactions + categories repos, SyncEngine | Offline expense on A shows on B, no duplicates, restart-safe |
| 4 | Categories, transactions (filters), budgets, dashboard, settings/sign-out | All P0 features work offline on Windows |
| 5 | Retry/backoff, triggers, sync status, conflict UI, workmanager | Every release gate in testing.md passes |
| 6 | Adaptive layout (rail/table on desktop), theme, a11y | Usable at phone and desktop widths |
| 7 | CI, Windows/APK builds, README polish | CI green on main |

Dependencies: 1 and 2 → 3 → 4 → 5. Phase 6 can overlap with 4 and 5.

## v2: Freelancer workspace, analytics, insights, AI

Billing is out of scope. Everything below is free.

| # | Phase | Gate |
|---|---|---|
| 8 | Workspace column, server + Drift v1→v2 migration ([0006](decisions/0006-workspaces-as-column.md)) | An op queued on v1.0.0 still syncs after upgrade. pgTAP rejects a cross-workspace category. Migration test keeps all v1 data |
| 9 | Workspace switcher, repositories and providers scoped by workspace, enable Freelancer | Personal rows never appear in Freelancer screens or totals, on both devices |
| 10 | Personal analytics: month-over-month, category breakdown, income vs. expense chart, budget health (days left, pace) | Totals match fixture data per currency. Chart goldens pass |
| 11 | Clients and projects ([0007](decisions/0007-freelancer-records.md)), generalized parent hold-back | Two-device sync of both. A child created offline with its new parent pushes in order |
| 12 | Invoices, payments, invoiced vs. received, overdue, project profit | Totals match fixture data per client, project and currency. A number collision becomes a conflict. Overdue flips at the due date |
| 13 | Rule-based insights and category suggestions (local, computed on read) | Each rule unit-tested. Works offline |
| 14 | Ask Budgity via Edge Function ([0008](decisions/0008-ai-assistant.md)) | Rejects unauthenticated calls and enforces the limit. A test proves the payload has no descriptions. App works with the function down |

Dependencies: 8 → 9 → 10 and 11 → 12. 13 needs 10 (and 12 for invoice rules). 14 needs 10.
Phase 10 picks the chart approach (`fl_chart` or `CustomPaint`).
