---
id: 20260506231740
aliases: ["hook-state"]
tags: ["shell", "storage", "boundary"]
---
`hook-state/` stores disposable JSON state for shell hook adapters. It is not canonical history.

## What

Each generated shell integration calls the `histlog` executable for session start, pre-command, post-command, and session end hooks. Since those calls are separate OS processes in v1, `Histlog.Hook` persists the active writer state under `hook-state/`.

## Why

The hook boundary keeps shell scripts thin and centralizes validation, redaction, and append-only writes in Elixir. The JSON state file is the small bridge that lets short-lived hook commands share one session writer without requiring a daemon.

## Rules

- `hook-state/*.json` is ephemeral adapter state.
- `sessions/**/*.ndjson` is canonical history.
- Deleting hook state may lose adapter continuity, but it must not mutate existing history.
- Broken hook state should be recovered or ignored without corrupting session NDJSON.

## Links

- [[Shell Hook CLI Boundary]] - Defines the shell-to-Elixir runtime boundary.
- [[NDJSON Boundary Contract]] - Defines canonical persisted history.
- [[Session Logfile Per CLI Session]] - Defines one append-only event stream per session.
