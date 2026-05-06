---
id: 20260507005320
aliases: ["no daemon", "no long-running OTP service"]
tags: ["architecture", "runtime"]
---
Histlog must remain a short-lived CLI/escript tool and must not become a daemon or long-running OTP service.

## What

Every workflow runs through `histlog ...` CLI invocations: shell hooks, query, paths, sessions, import, verify, and consolidate. Recurring work may be driven by cron, launchd, systemd timers, or other external schedulers, but the histlog process exits after completing the command.

## Why

Shell history capture should stay simple, inspectable, reversible, and easy to debug. Avoiding resident services removes lifecycle management, IPC, daemon permissions, and service recovery from the core product.

## How

Package the user-facing command as an escript. For local development, install it by symlinking `~/.local/bin/histlog` to the repo-built `app/histlog` so shell hooks pick up rebuilds immediately. Store any cross-invocation adapter state explicitly in files such as `hook-state/`, and keep canonical history in NDJSON.

## Links

- [[Elixir Implementation Language]] - Defines Elixir as the short-lived CLI implementation language.
- [[Ephemeral Hook State]] - Bridges shell hook invocations without a daemon.
- [[NDJSON Boundary Contract]] - Keeps persisted files as the integration contract.
