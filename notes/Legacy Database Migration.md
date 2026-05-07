---
id: 20260507161000
aliases: ["legacy histlog db migration", "histlog2 db migration"]
tags: ["migration", "sqlite", "maintenance"]
---
Legacy histlog SQLite databases can be imported with a standalone maintenance script.

## Decision

Do not add legacy DB migration as a public `histlog` CLI command.
Keep it under `scripts/migrate-legacy-histlog-db.exs` so the main application does not carry a compatibility path.

## Behavior

The script backs up the original database, creates a fresh database with the current projection schema, and imports legacy sessions, commands, paths, shells, and TTYs.

Session-backed legacy commands become `source = "session"` projection rows with synthetic `legacy:<id>` session IDs.
Legacy commands without a session become `source = "import"` rows in the `legacy-histlog-db-orphans` import batch.

## Links

- [[SQLite Consolidation Schema]] - Defines the target projection schema.
- [[Daily Rebuild Verification]] - Explains why normal rebuilds prefer canonical evidence.
