---
id: 20260506222908
aliases: ["checkpointing", "processed sessions"]
tags: ["integrity", "consolidation"]
---
Histlog consolidation should record checkpoint metadata so database materialization is idempotent and auditable.

## What

Consolidation metadata records processed sessions, record counts, schema version, materialization timestamps, and source checksums. It is the checkpoint that prevents reprocessing the same closed session during future consolidation runs.

## Why

Database materialization shifts integrity work into the application. Checkpoints make this work explicit: operators and tests can see what was processed, what was skipped, and which schema version produced the materialized database.

## How

Write checkpoint metadata in the same SQLite transaction that materializes closed sessions into `$HISTLOG_ROOT/histlog.db`. Consolidators should read existing checkpoint rows before processing and skip only when date, session file, source checksum, and schema version all match.

`histlog doctor` recomputes expected record counts and schema facts from the database and compares them to the checkpoint. Verification is read-only; rebuild support is a separate operational workflow.

`histlog db rebuild` recreates the materialized database from closed session files. It does not need to preserve compatibility with `histlog2` tables or migrations.

## Links

- [[Daily Finished Session Consolidation]] - Produces checkpoint metadata as part of materialization.
- [[Daily Rebuild Verification]] - Defines read-only verification of materialized database state.
- [[SQLite Consolidation Schema]] - Defines the checkpoint tables and schema version ownership.
- [[Minimal Overhead Constraint]] - Allows checkpoint work outside the interactive shell path.
