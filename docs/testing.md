# Testing

| Layer | Tool | Covers |
|---|---|---|
| Unit | `flutter_test` | Money parse/format/precision, budget math, queue coalescing, SyncEngine against `FakeRemoteSyncApi` |
| DB | Drift `NativeDatabase.memory()`, `SchemaVerifier` | DAOs, migrations keep data |
| Widget | `flutter_test` with fake repositories | Transaction form validation, dashboard totals |
| Backend | pgTAP (`supabase test db`) | RLS isolation, anon denied, version conflicts, idempotent replay, batch isolation, `blocked` |
| Integration | `test/integration/` + local Supabase | Two in-memory devices, one user, real sync |

CI runs all of these on every PR (see `.github/workflows/ci.yml`).

## Release gates (manual, two Windows instances, then Windows + Android)

- [ ] Expense created offline on A appears on B after reconnecting, and the reverse
- [ ] Same record edited on both devices raises a conflict, and either choice resolves it
- [ ] Timeout after the server commits, then retry: no duplicate
- [ ] Offline delete propagates
- [ ] Kill the app with pending ops and restart: they sync
- [ ] Expired session: data still available, sync resumes after sign-in
- [ ] Another user's rows are not visible (RLS)
- [ ] Schema upgrade preserves data
- [ ] TND (3 dp) and EUR (2 dp) totals are exact
- [ ] Long offline period with many queued ops syncs cleanly
