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

SQLite gives the CLI fast query, session, path, and doctor workflows without turning histlog into a long-running service. `histlog info` reports runtime inventory without reading or validating the database. Because closed session logs remain the source input for consolidation, the database can be rebuilt when the schema changes.

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
- command argument path facts in `command_paths`
- query views that join normalized tables back into user-facing rows
- indexes for date, timestamp, command text, cwd, exit status, source, and import batches

Base tables are internal projection storage. Query code should prefer `history_view` for command history and `sessions_view` for session summaries unless a targeted maintenance task needs base-table access.

Processed-session skip logic must compare date, session file, source checksum, and schema version. A closed session file with the same name but different content must be reprocessed.

The command projection should keep basic integrity constraints, including non-negative durations, an allowed `completeness` enum, and source-specific identity checks for `session` and `import` rows.
Missing or empty command text is invalid projection input; do not silently insert empty strings into `cmd_texts`.
Stored command sources are `session` and `import`; live commands are derived from active session NDJSON at query time and are not written to SQLite.
Imported commands use `source = "import"` plus `import_batch_id` and `import_row_index` for stable identity. Query code should not scan import NDJSON directly.

`command_paths` stores derived command argument path facts keyed to materialized command rows. These rows are not canonical history; they are rebuildable analysis products derived from command text and cwd during consolidation or import materialization.
Paths under `System.user_home!()` are normalized to `~` before materialization so the database does not repeat a machine-specific absolute home directory. This normalization must not hardcode a username or platform-specific home path.

Use explicit schema versioning. During this early rewrite, incompatible projection schemas are dropped and rebuilt from canonical NDJSON rather than migrated in place. Consolidation reports this as `schema_reset: true`.

## Links

- [[Daily Finished Session Consolidation]] - Writes this database from closed sessions.
- [[Checkpointing]] - Tracks processed sessions and schema version.
- [[Query Source Union]] - Requires queries to merge SQLite rows with live session NDJSON.
- [[Histlog2 Functional Blueprint]] - Reuses product behavior without schema compatibility.
