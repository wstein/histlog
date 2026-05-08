---
id: 20260506233320
aliases: ["histlog doctor database", "consolidation verification"]
tags: ["integrity", "operations", "consolidation", "sqlite"]
---
Verification checks whether the consolidated database still matches the consolidation checkpoint.

## What

`histlog doctor` should validate `$HISTLOG_ROOT/histlog.db` against consolidation metadata. Verification should report missing tables, schema mismatches, record-count drift, and processed-session inconsistencies.

## Why

Consolidation is trustworthy only if the materialized database and the processed-session checkpoint agree. Users may edit, sync, or corrupt files outside histlog, so operators need a read-only way to detect drift before trusting query results.

## How

Verification does not repair the database. `histlog info` shows passive runtime inventory only; `histlog doctor` adds diagnostic detail and recommendations, and returns the full verifier report through `histlog doctor --json`. `histlog rebuild` can then regenerate the database from current closed sessions.

Consolidation should use a transaction when updating `histlog.db`. A later run must recover or retry safely so a crash during database materialization does not cause duplicate rows or a partially trusted checkpoint.
If the derived database schema is incompatible and gets reset, the consolidation report must expose that reset so operators are not surprised by a rebuild.

## Links

- [[Checkpointing]] - Defines the checkpoint rows verified here.
- [[Daily Finished Session Consolidation]] - Produces the materialized database.
- [[SQLite Consolidation Schema]] - Defines the tables verification should inspect.
- [[Corruption Quarantine]] - Handles malformed session inputs before materialization.
