---
id: 20260507173000
aliases: ["histlog statistics", "history statistics"]
tags: ["cli", "query", "analytics"]
---
`histlog statistics` reports high-level history counts and top lists over the shared query row stream.

## What

The command summarizes total commands, unique commands, sessions, imported commands, live commands, successful commands, failed commands, first/last timestamps, top commands, and top paths.

## Why

Statistics are useful for dogfooding and operational confidence, but they should not create a separate analytics database or a new read path.

## How

`Histlog.Query.Statistics` consumes execution rows returned by `Histlog.Query.executions/1`. The CLI command only parses options and renders table, JSON, or plain output.

## Links

- [[Query Source Union]] - Defines the DB plus live row stream.
- [[Command Discovery]] - Provides top command aggregation.
- [[Filesystem Path Analysis]] - Provides top path aggregation.
