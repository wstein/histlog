---
id: 20260506222906
aliases: ["ndjson boundary", "file boundary"]
tags: ["architecture", "boundary"]
---
Histlog subsystems should communicate through NDJSON files rather than shared mutable runtime state.

## What

Writers, importers, consolidators, and query code use persisted NDJSON streams as their integration contract. Elixir modules may share parsing and validation libraries, but subsystem state crosses boundaries through files.

## Why

The event log is the system's canonical truth. Treating NDJSON as the runtime boundary prevents hidden coupling between shell capture, batch consolidation, and future query or MCP layers.

## How

Do not add global GenServers, ETS tables, or direct state handoffs that make one subsystem depend on another subsystem's memory. Persist events first, then let other components consume the files.

## Links

- [[NDJSON Log Format]] - Defines the physical line-oriented event format.
- [[Elixir Implementation Language]] - Defines Elixir as the orchestration layer for these boundaries.
- [[Daily Finished Session Consolidation]] - Consumes closed NDJSON files through this boundary.
