---
id: 20260507004000
aliases: ["histlog2 blueprint", "functional blueprint"]
tags: ["cli", "product", "compatibility"]
---

Use mature `histlog2` behavior as the product blueprint for the Elixir rewrite where it improves the user-facing CLI.

## What

`histlog2` already defines practical command surfaces for query, sessions, import, paths, init, and database maintenance. The Elixir implementation should reuse those good interface ideas while preserving its own v1 architecture: append-only session files, SQLite consolidation to `$HISTLOG_ROOT/histlog.db`, and no long-running service. Backward compatibility with the `histlog2` schema is not required.

## Why

The Ruby implementation has already absorbed real user workflow pressure. Reusing its public behavior avoids re-learning solved interface details while the Elixir rewrite changes the storage architecture.

## How

The Elixir CLI should follow the `histlog2` model for rich query output, filesystem path summaries, and session listing. The blueprint is functional first, but the mature `histlog2` relational model is also a useful comparison point. Reuse good schema ideas, such as command text and path dimensions, without copying migrations, table names as a compatibility contract, or legacy identifiers into v1.

Every imported behavior must pass the intake gate: it must operate over `$HISTLOG_ROOT/histlog.db` plus live session rows without mutating canonical events. Import artifacts enter the query path only after materialization.

## Links

- [[CLI Option Parsing]] - Defines command-specific public option parsing.
- [[Filesystem Path Analysis]] - Adapts the mature path summary behavior.
- [[Functional Blueprint Intake Gate]] - Sets the rule for admitting blueprint behavior into v1.
- [[SQLite Consolidation Schema]] - Owns the rewrite-native database shape.
- [[No Long Running Service]] - Preserves the short-lived escript runtime model.
