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

It stores a query-ready relational projection derived from closed session logs and import artifacts. It is a materialized view, not the canonical capture artifact.

## Why

SQLite gives the CLI fast query, session, path, and verification workflows without turning histlog into a long-running service. Because closed session logs remain the source input for consolidation, the database can be rebuilt when the schema changes.

Query commands must not rely only on SQLite. They must also include live session NDJSON so current commands appear before consolidation runs.

## Schema Ownership

The Elixir rewrite owns the schema. It may update tables, indexes, views, and metadata as needed for the current product behavior.

No backward compatibility with `histlog2` tables, views, migrations, or identifiers is required.
The schema may still learn from `histlog2`'s mature relational shape: command text, paths, shells, ttys, sessions, imports, and commands are separate concepts instead of one flat execution table.

SQLite access uses `exqlite` directly through a small `Histlog.Database` wrapper. The project should not add a larger persistence framework unless the query model outgrows explicit SQL.

## Projection Shape

The v1 schema supports:

- schema metadata and version
- processed session checkpoint rows keyed by `(date, session_file)`
- hosts, shells, ttys, and paths as shared dimensions
- sessions keyed by canonical session identity
- import batches with report/provenance metadata
- command text interning in `cmd_texts`
- command projection rows in `commands`
- query views that join normalized tables back into user-facing rows
- indexes for date, timestamp, command text, cwd, exit status, source, and import batches

Processed-session skip logic must compare date, session file, source checksum, and schema version. A closed session file with the same name but different content must be reprocessed.

The command projection should keep basic integrity constraints, including non-negative durations and an allowed `completeness` enum.
Imported commands use `source = "import"` plus `import_batch_id` and `import_row_index` for stable identity. Query code should not scan import NDJSON directly.

Use explicit schema versioning so `histlog consolidate --rebuild` can recreate the database when the schema changes.

## Links

- [[Daily Finished Session Consolidation]] - Writes this database from closed sessions.
- [[Checkpointing]] - Tracks processed sessions and schema version.
- [[Query Source Union]] - Requires queries to merge SQLite rows with live session NDJSON.
- [[Histlog2 Functional Blueprint]] - Reuses product behavior without schema compatibility.
