# 0008 AI assistant explains numbers the app computes

**Status:** accepted

**Context:** A model can't be trusted to add money, the repo is public, and only the publishable key may ship in the client (security.md).

**Decision:** Analytics are local Drift queries, scoped to one workspace and grouped by currency. "Ask Budgity" sends the question plus a fixed bundle of those computed aggregates (monthly totals, top categories, budget progress, invoiced vs. received) to a Supabase Edge Function. The function checks the JWT, enforces a per-user daily limit (server-only table), calls the model with the provider key held as a function secret, and returns text. The prompt tells the model to explain only the figures it was given. Raw transactions and descriptions never leave the device. The client talks to the function, not a provider, so the model can be swapped.

**Consequences:** The assistant needs network; every other feature works without it. A question the bundle can't answer gets "I don't have that data" rather than a guess. Tool calling (the model asks the app for a specific query) and receipt extraction are later upgrades over the same function.
