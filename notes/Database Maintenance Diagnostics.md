---
id: 20260507173500
aliases: ["db maintenance", "sqlite diagnostics"]
tags: ["sqlite", "doctor", "operations"]
---
`histlog doctor` includes read-only SQLite maintenance diagnostics for the derived query projection.

## What

Doctor runs SQLite integrity and orphan relationship checks alongside schema and materialization-count verification.

## Why

`histlog.db` is derived, but it is still the hot query surface. Users need clear diagnostics when the projection is corrupt, stale, or internally inconsistent.

## How

`Histlog.Database.Maintenance` opens the database read-only, runs `PRAGMA integrity_check`, and verifies that projection relationship rows still point at their owning tables.

The remedy for failed projection diagnostics is rebuild, not mutation of canonical NDJSON evidence.

## Links

- [[SQLite Consolidation Schema]] - Defines projection tables and relationships.
- [[Daily Rebuild Verification]] - Documents rebuild and verification behavior.
- [[NDJSON Boundary Contract]] - Keeps canonical evidence separate from derived projection state.
