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

## Links

- [[Shell Init Prints Integration Code]] - Produces the scripts under test.
- [[Shell Hook CLI Boundary]] - Defines the hook commands called by generated scripts.
- [[Ephemeral Hook State]] - Explains the adapter state used across hook invocations.
