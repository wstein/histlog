---
id: 20260506234310
aliases: ["shell smoke tests"]
tags: ["testing", "shell"]
---
Real shell smoke tests source generated init scripts in shell subprocesses.

## What

The smoke suite creates a temporary `histlog` executable wrapper, runs zsh, bash, and fish when they are available, sources `histlog init SHELL`, exercises the generated hook functions, and validates the resulting closed session NDJSON.

## Why

Unit tests can verify generated strings, but shell integration bugs often come from quoting, function syntax, traps, and shell-specific behavior. Real shell subprocesses catch those issues earlier.

## How

Smoke tests should remain hermetic: use a temporary `HISTLOG_ROOT`, skip unavailable shells, avoid user rc files, and validate the resulting NDJSON through the same schema used by consolidation.

Live sessions are queryable before consolidation. `histlog query` derives query rows from active `sessions/live/session-*.ndjson` files without exposing raw canonical records as a public CLI format.

Smoke tests should verify the source union: after some history has been consolidated to SQLite, new commands in the same active shell must still appear in `histlog query`, `histlog sessions`, and `histlog paths`.

Bash smoke tests cover histlog's generated `DEBUG` trap in a clean shell. They do not prove compatibility with an existing user `DEBUG` trap, because v1 installs histlog's trap directly instead of composing arbitrary pre-existing trap code.

## Links

- [[Shell Init Prints Integration Code]] - Produces the scripts under test.
- [[Shell Hook CLI Boundary]] - Defines the hook commands called by generated scripts.
- [[Ephemeral Hook State]] - Explains the adapter state used across hook invocations.
