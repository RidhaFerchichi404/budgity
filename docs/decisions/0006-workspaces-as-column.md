# 0006 Workspaces as a column, not a table

**Status:** accepted

**Context:** One account needs separate Personal and Freelancer data. A synced `workspaces` table would be a new parent entity: push ordering, hold-back, and a deterministic Personal id so two offline devices don't each create one.

**Decision:** `categories`, `transactions` and `budgets` get `workspace text not null default 'personal' check (workspace in ('personal','freelancer'))`. Categories add `unique (id, user_id, workspace)` and the category FKs become `(category_id, user_id, workspace)`, so a row can never use another workspace's category. Clients, projects, invoices and payments are freelancer-only and carry no column. `sync_push` treats a missing `workspace` as `personal`, so v1.0.0 clients and ops queued before the upgrade keep working. Freelancer is turned on by a `profiles.freelancer_enabled` flag; `update_profile` seeds its default categories server-side the first time it flips, like signup does, so two devices never seed duplicates.

**Consequences:** Adding a column with a constant default is metadata-only in Postgres: no row rewrite, the `change_seq` trigger doesn't fire, versions don't change, and pending ops don't conflict. Drift v1→v2 adds the same column with the same default. An account gets exactly one Personal and one Freelancer workspace; shared workspaces or several businesses would need a real `workspaces` table (convert the column into an FK then). A v1.0.0 device shows freelancer rows as personal, so every device must update before Freelancer is enabled.
