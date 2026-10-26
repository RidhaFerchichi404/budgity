# Synchronization

## Local write

`repository.create/update/delete` runs in one Drift transaction:
1. Write the row (deletes set `deleted_at`).
2. Enqueue an op, coalescing only with a **never-sent** op (`attempt_count = 0`, status `pending`)
   for the same entity:
   - create + update → create (latest payload)
   - update + update → update (latest payload)
   - create + delete → both removed (the server never saw it)
   - anything + an already-sent op → a new op with a new id

## Cycle (`SyncEngine.run`)

1. **Ready?** Not already running (in-memory lock + DB lease), a session exists, and the network is reachable
   (verified by the request itself, not just the connectivity flag).
2. **Push.** Due ops (`next_attempt_at <= now`, status `pending`) are sent in dependency order:
   categories → transactions → budgets. An op whose parent category still has an unacked,
   failed, or conflicted op is held back. `base_version` is read from the local row **at push time**.
3. **Handle results** per op:
   | Result | Action |
   |---|---|
   | `applied` / `duplicate` | Write the server `version`/`change_seq` to the local row and delete the op |
   | `conflict` | op → `conflict`, insert into `sync_conflicts` (local payload, server row) |
   | `invalid` | op → `failed` with message, never retried automatically |
   | `blocked` (missing parent) | stays `pending`, retried with backoff |
   | network/5xx/timeout | backoff `min(2^n·5s, 1h) ± 20%`, op unchanged |
   | 401 | refresh the session. If that fails, stop and show "Sign in required" (not counted as a failure) |
   | 429 | wait for Retry-After |
4. **Pull** each table in dependency order: `change_seq > cursor order by change_seq limit 500`, looping until empty.
5. **Apply** in one Drift transaction per page. Rows whose entity has any queued op are skipped (the
   op will push or conflict). No queue ops are created. Then **advance the cursor** in the same transaction.
6. **Status.** Record the last successful sync time. Pending, failed, and conflict counts are live queries.

## Why the cursor is safe

`change_seq` comes from one sequence, assigned by trigger. All writes go through `sync_push`, which takes
`pg_advisory_xact_lock(hashtext(user_id::text))`, so a user's changes commit in seq order and a reader
can't see seq N+1 before N commits.

## Idempotency

Each op carries its uuid. `sync_push` records `(op_id, result)` in `sync_operations` inside the same
subtransaction as the write, so a replay after a timeout returns the stored result and creates no duplicate.

## Conflicts

- **Keep mine:** re-queue the local payload with `base_version = server.version`.
- **Keep server:** apply the stored server row locally and drop the op.
- Edit-vs-delete uses the same screen. Nothing is auto-merged. An applied update always clears
  `deleted_at`, so *keep mine* on an edit-vs-delete conflict restores the record on every device.
- **Discard a failed op:** fetch the entity by id from the server and apply it. If the server has no row, delete it locally.

## Triggers

App start, resume, 2 s after a local write, connectivity regained, a 5-min foreground timer, and Android
`workmanager` (15 min, network required, skipped while the app is in the foreground).

## Profiles

Last-write-wins via `update_profile` RPC. The server sets `updated_at`.
