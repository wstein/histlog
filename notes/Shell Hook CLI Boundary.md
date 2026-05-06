---
id: 20260506224845
aliases: ["hook cli", "histlog hook"]
tags: ["shell", "boundary"]
---
Generated shell integration should call `histlog hook ...` commands and leave validation, redaction, and append-only writes to Elixir.

## What

The shell adapter captures lifecycle facts and invokes `histlog hook session-start`, `preexec`, `precmd`, and `session-end`. The shell must not construct NDJSON directly.

`hook-state/*.json` files are allowed only as ephemeral adapter state between separate hook invocations. They are not part of canonical history; only `sessions/**/*.ndjson` is historical truth.

## Why

Shells are good capture adapters but poor validation and persistence runtimes. Centralizing event construction in Elixir keeps redaction, schema checks, sequence enforcement, and storage layout consistent across zsh, bash, fish, and future shells.

## How

Keep generated scripts quoted and non-recursive. Suppress hook errors by default so history capture does not break interactive commands. Treat hook commands as internal but stable enough for generated scripts.

## Links

- [[Shell Init Prints Integration Code]] - Describes how users install the generated adapters.
- [[NDJSON Boundary Contract]] - Keeps persisted files as the subsystem boundary.
- [[Ephemeral Hook State]] - Documents the non-canonical hook adapter cache.
- [[Observed Execution Event]] - Defines the event emitted by pre/post command hooks.
