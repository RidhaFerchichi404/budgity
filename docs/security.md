# Security

## Cloud (Supabase)

- RLS is enabled on every table. Clients have **SELECT only**: `(select auth.uid()) = user_id`.
- `insert/update/delete` grants are revoked from `anon` and `authenticated`. All writes go through
  `sync_push` / `update_profile` (`security definer`, `set search_path = ''`), which:
  - reject a null `auth.uid()` and force `user_id = auth.uid()`
  - validate type, amount, currency, dates, and category ownership (composite FK)
  - check `base_version` atomically
- `execute` on RPCs is revoked from `public, anon` and granted to `authenticated` only.
- `sync_operations` has RLS on with no policies, so only the RPC can reach it.
- Expected Supabase advisor findings (by design, reviewed): *RLS enabled, no policy* on `sync_operations`,
  and *authenticated can execute SECURITY DEFINER* for `sync_push` / `update_profile`, which are the only
  write path and enforce `auth.uid()` themselves. Any other advisor finding is a bug.
- The client ships only the **publishable** key, passed in through `--dart-define-from-file=env.json` (gitignored).
  No service-role key anywhere in the repo.
- Email confirmation is **off for the MVP** (no deep-link handling on Windows/Android, and the built-in SMTP
  is rate-limited). Revisit before any public release.

## Device

- The Supabase session is stored with `flutter_secure_storage` (Android Keystore, Windows DPAPI).
  No passwords are stored.
- The SQLite file is **not encrypted** in the MVP (ADR 0004). It lives in the per-user app-support directory.
- Logs never include amounts, descriptions, or tokens.
- An expired session keeps local data readable and editable. Sync pauses until the user signs in again.
- Sign-out: final sync attempt → warn if ops are pending → close the DB → delete `.sqlite`, `-wal`, `-shm` → clear the session (ADR 0005).

## Threats considered

| Threat | Mitigation |
|---|---|
| Reading another user's data | RLS plus pgTAP tests with two users |
| Writing into another user's rows or categories | Definer RPC forces `auth.uid()`, plus composite FK |
| Stale or replayed writes | Version check plus op ledger |
| Leaked client binary | Holds only the publishable key, so RLS still applies |
| Stolen unlocked device | Out of scope for the MVP. Mitigated in P1 by DB encryption |
