---
id: 20260506233320
aliases: ["histlog verify", "consolidation verification"]
tags: ["integrity", "operations", "consolidation", "sqlite"]
---
Verification checks whether the consolidated database still matches the consolidation checkpoint.

## What

`histlog verify` should validate `$HISTLOG_ROOT/histlog.db` against consolidation metadata. Verification should report missing tables, schema mismatches, record-count drift, and processed-session inconsistencies.

## Why

Consolidation is trustworthy only if the materialized database and the processed-session checkpoint agree. Users may edit, sync, or corrupt files outside histlog, so operators need a read-only way to detect drift before trusting query results.

## How

Verification does not repair the database. It returns a report with an overall `ok` boolean and concrete errors. `histlog consolidate --rebuild` can then regenerate the database from current closed sessions.

Consolidation should use a transaction when updating `histlog.db`. A later run must recover or retry safely so a crash during database materialization does not cause duplicate rows or a partially trusted checkpoint.

## Links

- [[Manifest And Checkpointing]] - Defines the manifest fields verified here.
- [[Daily Finished Session Consolidation]] - Produces the materialized database.
- [[SQLite Consolidation Schema]] - Defines the tables verification should inspect.
- [[Corruption Quarantine]] - Handles malformed session inputs before materialization.
