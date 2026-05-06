---
id: 20260507011500
aliases: ["blueprint intake gate", "histlog2 intake gate"]
tags: ["cli", "product", "architecture"]
---
histlog2 behavior enters histlog v1 only through an explicit intake gate.

## What

The Elixir rewrite may adopt mature `histlog2` workflows when they improve the user-facing tool, but each imported behavior must fit the v1 file-backed architecture.

## Why

`histlog2` is a useful functional blueprint, but it also carries database-era assumptions. Without a gate, the rewrite can copy broad CLI complexity faster than the append-only storage and query model can support it cleanly.

## Gate

A behavior may enter v1 only when it can be implemented over one of these sources:

- daily execution rows
- currently live session rows
- import event streams

The behavior must not mutate canonical session events. If it requires in-place history changes, resident indexing, SQL semantics, or a daemon, defer it outside v1.

## Links

- [[Histlog2 Functional Blueprint]] - Describes the source of reusable product behavior.
- [[NDJSON Boundary Contract]] - Defines file-backed subsystem boundaries.
- [[No Long Running Service]] - Keeps runtime work short-lived.
