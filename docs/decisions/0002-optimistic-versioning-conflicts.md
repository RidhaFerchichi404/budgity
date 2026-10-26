# 0002 Optimistic versioning and explicit conflicts

**Status:** accepted

**Context:** The same record can be edited offline on both devices. For financial data, silently picking a winner or merging fields is unacceptable.

**Decision:** Every row has `version`. Writes go through `sync_push`, which applies an op only if `base_version` matches, then increments the version. A mismatch returns `conflict` plus the server row, and the user chooses *keep mine* or *keep server*. Profiles are an exception and use last-write-wins (server timestamp).

**Consequences:** No silent data loss. Users sometimes have to resolve a conflict. The version check is atomic in Postgres, not trusted from the client.
