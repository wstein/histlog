---
id: 20260507171000
aliases: ["histlog commands", "command summaries"]
tags: ["cli", "query", "histlog2"]
---
`histlog commands` summarizes command usage over the shared query row stream.

## What

The command groups execution rows by command text and reports frequency, first/last use, session spread, directory spread, success count, and failure count.

## Why

The mature `histlog2` workflow includes command discovery separate from row-level history search. Keeping this as a first-class command makes common workflows faster without overloading `histlog query`.

## How

The CLI parses and renders. `Histlog.Query.Commands` owns the semantic aggregation so future API, MCP, or report surfaces can reuse the same behavior without invoking CLI code.

Inputs are the same as other query-family commands:

- materialized rows from `$HISTLOG_ROOT/histlog.db`
- currently live session NDJSON rows

Imports are included after `histlog import` materializes them into SQLite.

## Links

- [[Histlog2 Functional Blueprint]] - Supplies the mature command discovery behavior.
- [[Functional Blueprint Intake Gate]] - Allows only behavior that works over DB plus live rows.
- [[Query Source Union]] - Defines the query-family source contract.
