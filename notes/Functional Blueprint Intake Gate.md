---
id: 20260507011500
aliases: ["blueprint intake gate", "histlog2 intake gate"]
tags: ["cli", "product", "architecture"]
---
histlog2 behavior enters histlog v1 only through an explicit intake gate.

## What

The Elixir rewrite may adopt mature `histlog2` workflows when they improve the user-facing tool, but each imported behavior must fit the v1 architecture.

## Why

`histlog2` is a useful functional blueprint, but it also carries schema and compatibility assumptions. Without a gate, the rewrite can copy broad CLI complexity faster than the new capture and consolidation model can support it cleanly.

## Gate

A behavior may enter v1 only when it can be implemented over one of these sources:

- `$HISTLOG_ROOT/histlog.db`
- currently live session rows

For query-family behavior, SQLite and live session rows are not alternatives; both must be included.
Import streams enter SQLite before query-family behavior reads them.

The behavior must not mutate canonical session events. If it requires in-place history changes, a daemon, or compatibility with the `histlog2` database schema, defer it outside v1.

## Links

- [[Histlog2 Functional Blueprint]] - Describes the source of reusable product behavior.
- [[SQLite Consolidation Schema]] - Defines the native database materialization target.
- [[Query Source Union]] - Requires merged SQLite and live-session query behavior.
- [[No Long Running Service]] - Keeps runtime work short-lived.
