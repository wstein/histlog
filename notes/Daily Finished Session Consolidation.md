---
id: 20260506221341
aliases: ["24h consolidation", "daily consolidation"]
tags: ["consolidation", "operations"]
---
Histlog should consolidate finished CLI sessions every 24 hours so live session logs are periodically moved into durable historical storage.

## What

Every 24 hours, histlog identifies CLI sessions that have finished and consolidates their session logfiles into historical storage. Active sessions remain outside consolidation until they are finished.

## Why

Periodic consolidation keeps active command capture simple while still producing an analyzable historical store. The 24-hour cadence creates a predictable operational rhythm without requiring expensive processing after every command.

## How

Implement consolidation as a scheduled or explicitly triggered Elixir workflow that scans for finished sessions, validates their JSONL records, materializes consolidated output, and records enough state to avoid consolidating the same session twice.

## Links

- [[Session Logfile Per CLI Session]] - Provides the finished session logfiles consumed by consolidation.
- [[JSONL Log Format]] - Defines the input records consolidation must validate.
- [[Minimal Overhead Constraint]] - Explains why consolidation is deferred from the interactive capture path.
