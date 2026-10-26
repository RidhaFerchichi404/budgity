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
