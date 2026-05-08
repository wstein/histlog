---
id: 20260508111500
aliases: ["normalize db paths", "home path normalization"]
tags: ["sqlite", "paths", "maintenance"]
---
Existing `histlog.db` rows can be normalized with a standalone maintenance script after home-directory path normalization changes.

## Decision

Normalize paths under `System.user_home!()` to `~` for materialized path rows and path summaries.
Do not hardcode a user-specific path such as `/Users/werner`.

## Existing Databases

Use `scripts/normalize-db-paths.exs` to update existing SQLite rows in place.
The script creates a backup before changing the database, merges duplicate absolute and tilde path rows, updates foreign-key references, and normalizes legacy `command_paths.resolved_path` values when that column exists.

## Links

- [[SQLite Consolidation Schema]] - Defines the path projection tables.
- [[Session Layout Migration]] - Similar standalone maintenance pattern for early alpha storage cleanup.
