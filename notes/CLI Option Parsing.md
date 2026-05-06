---
id: 20260507000510
aliases: ["OptionParser", "cli options"]
tags: ["cli", "architecture"]
---
The public CLI uses Elixir `OptionParser` with command-specific switch schemas.

## What

`Histlog.CLI` dispatches to `Histlog.CLI.Commands.*` modules. Each command module owns its accepted switches, positional arguments, and workflow. Shared normalization lives in `Histlog.CLI.Options`.

## Why

The CLI has separate surfaces for consolidation, verification, query, import, shell hooks, init generation, completions, and doctor output. Command-specific parsing keeps option behavior explicit without adding a third-party CLI framework.

## How

Use kebab-case switches externally and snake_case atoms internally. Keep shell hook parsing narrow, since hooks are internal but still cross the shell boundary.

`histlog init --binary PATH` pins the executable path used by generated hooks. This reduces PATH-shadowing risk for users who want an explicit binary boundary.

## Links

- [[Shell Hook CLI Boundary]] - Defines the internal hook command surface.
- [[Shell Init Prints Integration Code]] - Generates setup code through the public CLI.
- [[Manifest And Checkpointing]] - Uses CLI commands for consolidation and verification.
