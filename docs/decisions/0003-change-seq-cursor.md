# 0003 Server change sequence as the pull cursor

**Status:** accepted

**Context:** `updated_at` cursors can miss rows that share a timestamp or are affected by clock skew.

**Decision:** A global sequence assigns `change_seq` by trigger on every insert and update. Clients pull `change_seq > cursor` in order. `sync_push` takes a per-user advisory lock, so a user's seqs commit in order.

**Consequences:** Each table needs one cursor, there are no duplicates, and nothing is missed. Writes are serialized per user, which is fine at personal-finance volume.
