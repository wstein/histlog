---
id: 20260507004000
aliases: ["histlog2 blueprint", "functional blueprint"]
tags: ["cli", "product", "compatibility"]
---

Use mature `histlog2` behavior as the product blueprint for the Elixir rewrite where it improves the user-facing CLI.

## What

`histlog2` already defines practical command surfaces for query, sessions, import, paths, init, and database maintenance. The Elixir implementation should reuse those good interface ideas while preserving its own v1 architecture: append-only session files, daily materialization, no database, and no long-running service.

## Why

The Ruby implementation has already absorbed real user workflow pressure. Reusing its public behavior avoids re-learning solved interface details while the Elixir rewrite changes the storage architecture.

## How

The Elixir CLI should follow the `histlog2` model for rich query output, filesystem path summaries, and session listing. The blueprint is functional, not architectural: do not copy SQLite-specific behavior into v1. Translate useful commands into file-backed operations over canonical session events and derived execution rows.

Every imported behavior must pass the intake gate: it must operate over daily execution rows, live session rows, or imports without mutating canonical events.

## Links

- [[CLI Option Parsing]] - Defines command-specific public option parsing.
- [[Filesystem Path Analysis]] - Adapts the mature path summary behavior.
- [[Functional Blueprint Intake Gate]] - Sets the rule for admitting blueprint behavior into v1.
- [[No Long Running Service]] - Preserves the short-lived escript runtime model.
