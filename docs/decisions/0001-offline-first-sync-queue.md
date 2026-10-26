# 0001 Offline-first with a durable sync queue

**Status:** accepted

**Context:** Users must be able to create, edit, and delete records with no network, on two devices that each have their own SQLite.

**Decision:** The UI reads only from local SQLite. Every mutation writes the row and a `sync_queue` op in one local transaction. A single `SyncEngine` pushes and pulls when it can.

**Consequences:** The UI never waits on the network, and no saved change can be "forgotten". We own a queue and state machine, with the complexity that brings (coalescing, retries, conflicts).
