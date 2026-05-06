---
id: 20260507002030
aliases: ["durability modes"]
tags: ["storage", "performance", "shell"]
---
Histlog session writers support `safe`, `balanced`, and `fast` durability modes.

## What

`safe` syncs every appended event. `balanced` syncs lifecycle events such as `session_started` and `session_ended`, while regular command/catalog events are appended without per-event fsync. `fast` appends without per-event fsync.

## Why

Interactive shell capture must stay low overhead, but some users prefer stronger crash durability. A mode makes the tradeoff explicit without changing the canonical NDJSON format.

## How

The default is `balanced`. Generated shell init code exports `HISTLOG_DURABILITY` and passes it to `histlog hook session-start`; hook state persists the selected mode for later hook invocations in the same session.

## Links

- [[Minimal Overhead Constraint]] - Drives the default toward balanced performance.
- [[Ephemeral Hook State]] - Persists the selected mode across hook invocations.
- [[Session Logfile Per CLI Session]] - Receives the durable append behavior.
