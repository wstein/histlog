---
id: 20260507103500
aliases: ["histlog.db", "sqlite consolidation schema"]
tags: ["sqlite", "consolidation", "schema"]
---
`histlog.db` is the rewrite-native SQLite materialization produced by `histlog consolidate`.

## What

The default consolidation database is:

```text
$HISTLOG_ROOT/histlog.db
```

It stores query-ready rows derived from closed session logs. It is a materialized view, not the canonical capture artifact.

## Why

SQLite gives the CLI fast query, session, path, and verification workflows without turning histlog into a long-running service. Because closed session logs remain the source input for consolidation, the database can be rebuilt when the schema changes.

## Schema Ownership

The Elixir rewrite owns the schema. It may update tables, indexes, views, and metadata as needed for the current product behavior.

No backward compatibility with `histlog2` tables, views, migrations, or identifiers is required.

## Initial Shape

The schema should support at least:

- schema metadata and version
- processed session checkpoint rows
- sessions
- commands
- working directories and path arguments
- imports
- verification metadata

Use explicit schema versioning so `histlog consolidate --rebuild` can recreate the database when the schema changes.

## Links

- [[Daily Finished Session Consolidation]] - Writes this database from closed sessions.
- [[Manifest And Checkpointing]] - Tracks processed sessions and schema version.
- [[Histlog2 Functional Blueprint]] - Reuses product behavior without schema compatibility.
