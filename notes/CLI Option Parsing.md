---
id: 20260507000510
aliases: ["OptionParser", "cli options"]
tags: ["cli", "architecture"]
---
The public CLI uses Elixir `OptionParser` with command-specific switch schemas.

## What

`Histlog.CLI` dispatches to `Histlog.CLI.Commands.*` modules. Each command module owns its accepted switches, positional arguments, and workflow. Shared normalization lives in `Histlog.CLI.Options`.

## Why

The CLI has separate surfaces for consolidation, info, doctor diagnostics, query, import, shell hooks, and init generation. Command-specific parsing keeps option behavior explicit without adding a third-party CLI framework.

## How

Use kebab-case switches externally and snake_case atoms internally. Keep shell hook parsing narrow, since hooks are internal but still cross the shell boundary.

Public filters must fail loudly when the user supplies malformed syntax. Invalid regular expressions, dates, integers, and duration filters should return CLI errors instead of empty result sets.

`histlog init --binary PATH` pins the executable path used by generated hooks. This reduces PATH-shadowing risk for users who want an explicit binary boundary. When this option is supplied, the path must be absolute and generated init code must assign `HISTLOG_BIN` directly rather than treating the path as an environment default.

`histlog init --durability safe|balanced|fast` sets the generated hook default for writer fsync behavior.

`histlog query` exposes human-facing formats and filters. NDJSON is a storage and subsystem boundary, not a public query output format; use `--json`, `--yaml`, `--plain`, or shell-specific `--format` values for CLI output. Use `histlog export --format ndjson` when a pipeline needs line-oriented JSON rows.

`histlog commands` is a public query-family command for command discovery. It accepts a positional search term and command-specific switches such as `--regex`, `--fuzzy`, `--session`, `--dir`, `--sort-by`, `--context`, `--plain`, and `--json`.

`histlog statistics` is a public query-family command for high-level counts and top lists. It should share query semantics rather than implement its own storage reads.

All query-family commands must apply parsing, filtering, sorting, and rendering after merging consolidated SQLite rows with live session NDJSON rows. Command-specific option parsing should not accidentally limit results to only one source.

## Links

- [[Shell Hook CLI Boundary]] - Defines the internal hook command surface.
- [[Shell Init Prints Integration Code]] - Generates setup code through the public CLI.
- [[Durability Mode]] - Defines the durability option passed through generated hooks.
- [[Checkpointing]] - Uses CLI commands for consolidation and doctor diagnostics.
- [[Functional Blueprint Intake Gate]] - Limits histlog2 behavior intake to file-backed v1 operations.
- [[Query Source Union]] - Defines the shared query source contract.
- [[Command Discovery]] - Defines command usage summaries over query rows.
- [[History Statistics]] - Defines high-level summary reporting over query rows.
