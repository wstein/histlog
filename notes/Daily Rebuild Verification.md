---
id: 20260506233320
aliases: ["histlog verify", "daily verification"]
tags: ["integrity", "operations", "consolidation"]
---
Daily verification checks whether materialized files still match the manifest checkpoint.

## What

`histlog verify --date YYYY-MM-DD` reads the daily manifest, recomputes record counts and SHA-256 checksums for `daily/YYYY-MM-DD.ndjson` and `daily/YYYY-MM-DD.exec.ndjson`, and reports mismatches.

## Why

Consolidation is idempotent only if the manifest and materialized files agree. Users may edit, sync, or corrupt files outside histlog, so operators need a read-only way to detect drift before trusting query results.

## How

Verification does not repair files. It returns a JSON report with per-file checks and an overall `ok` boolean. `histlog consolidate --rebuild --date YYYY-MM-DD` can then regenerate daily materializations from current closed sessions.

## Links

- [[Manifest And Checkpointing]] - Defines the manifest fields verified here.
- [[Daily Finished Session Consolidation]] - Produces the materialized files.
- [[Corruption Quarantine]] - Handles malformed session inputs before materialization.
