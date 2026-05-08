---
id: 20260506221341
aliases: ["24h consolidation", "session consolidation"]
tags: ["consolidation", "operations", "sqlite"]
---
`histlog consolidate` materializes finished CLI sessions into the local histlog database.

## What

Histlog identifies sessions that have finished and consolidates their session logfiles into `$HISTLOG_ROOT/histlog.db`. Active sessions remain outside consolidation until they are finished.

The default database path is:

```text
$HISTLOG_ROOT/histlog.db
```

## Why

Consolidation keeps active command capture simple while still producing an analyzable historical store. The database is a materialized view of closed session logs, not the live capture mechanism.

## How

Implement consolidation as an explicitly triggered or externally scheduled Elixir workflow:

1. scan closed session files
2. validate session records and sequence numbers
3. derive command/session/path rows
4. materialize those rows into `$HISTLOG_ROOT/histlog.db`
5. record enough consolidation state to avoid processing the same session twice

`histlog consolidate` without a date scans every dated closed-session directory. `histlog consolidate --date YYYY-MM-DD` is the narrow form for one date. This keeps query-family commands from depending on direct closed-NDJSON scans while still making one materialization pass enough to index all finished sessions.

The SQLite schema is owned by this Elixir rewrite and may change as needed. There is no backward-compatibility requirement with the `histlog2` schema.

## Links

- [[Session Logfile Per CLI Session]] - Provides the finished session logfiles consumed by consolidation.
- [[NDJSON Log Format]] - Defines the input records consolidation must validate.
- [[SQLite Consolidation Schema]] - Defines the local database materialization target.
- [[Minimal Overhead Constraint]] - Explains why consolidation is deferred from the interactive capture path.
