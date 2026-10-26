# 0005 Sign-out purges local data

**Status:** accepted

**Context:** Leftover financial data after sign-out is a privacy risk, and keeping per-user DBs adds complexity.

**Decision:** On sign-out: attempt a final sync. If ops are still pending, warn that they will be lost and require confirmation. Then close Drift, delete `.sqlite`, `-wal`, and `-shm`, and clear the session.

**Consequences:** Signing back in re-downloads everything. Unsynced changes are only lost if the user explicitly confirms.
