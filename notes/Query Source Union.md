---
id: 20260507104500
aliases: ["query sources", "sqlite plus live sessions"]
tags: ["query", "sqlite", "sessions"]
---
All query-family commands must read from both consolidated SQLite history and live session NDJSON.

## What

Commands such as `histlog query`, `histlog sessions`, `histlog paths`, and `histlog export` must combine:

- consolidated rows from `$HISTLOG_ROOT/histlog.db`
- currently live session logs from `sessions/live/**/*.ndjson`
- imports, when the command's behavior includes imported history

Closed sessions that have already been consolidated should come from SQLite. Active sessions that have not yet been consolidated should come from session NDJSON.

## Why

Users expect query results to include both stable history and the commands from the shell they are currently using. SQLite makes historical queries fast, but live session NDJSON closes the freshness gap before consolidation runs.

## How

Use a query source union:

1. read consolidated rows from `histlog.db`
2. derive live execution rows from active session NDJSON
3. read import execution rows where relevant
4. merge rows into one normalized execution shape
5. apply filters, sorting, formatting, path summaries, and session summaries after the merge

If a row appears in both sources, prefer the consolidated SQLite row and avoid duplicate display.
If SQLite cannot be read because of schema mismatch or corruption, query code should warn and continue with live/import rows. Silent loss of consolidated history is not acceptable.

## Links

- [[SQLite Consolidation Schema]] - Defines the consolidated query source.
- [[Session Logfile Per CLI Session]] - Defines live session NDJSON.
- [[CLI Option Parsing]] - Routes public query-family commands through shared query behavior.
