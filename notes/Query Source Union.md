---
id: 20260507104500
aliases: ["query sources", "sqlite plus live sessions"]
tags: ["query", "sqlite", "sessions"]
---
All query-family commands must read from consolidated SQLite history and live session NDJSON only.

## What

Commands such as `histlog query`, `histlog sessions`, `histlog paths`, and `histlog export` must combine:

- consolidated rows from `$HISTLOG_ROOT/histlog.db`
- currently live session logs from `sessions/live/**/*.ndjson`

Closed sessions that have already been consolidated should come from SQLite. Active sessions that have not yet been consolidated should come from session NDJSON.
Import streams are canonical audit artifacts, but they must be materialized into SQLite before query-family commands see them.

## Why

Users expect query results to include both stable history and the commands from the shell they are currently using. SQLite makes historical queries fast, but live session NDJSON closes the freshness gap before consolidation runs.
Imports are completed evidence streams, like closed sessions, so repeatedly scanning import NDJSON in every query would add permanent parser complexity and inconsistent performance.

## How

Use a query source union:

1. read consolidated rows from `histlog.db`
2. derive live query rows from active session NDJSON
3. merge rows into one normalized query shape
4. apply filters, sorting, formatting, path summaries, and session summaries after the merge

If a row appears in both sources, prefer the consolidated SQLite row and avoid duplicate display.
If SQLite cannot be read because of schema mismatch or corruption, query code should warn and continue with live rows. Silent loss of consolidated history is not acceptable.

## Links

- [[SQLite Consolidation Schema]] - Defines the consolidated query source.
- [[Session Logfile Per CLI Session]] - Defines live session NDJSON.
- [[CLI Option Parsing]] - Routes public query-family commands through shared query behavior.
