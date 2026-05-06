---
id: 20260506221343
aliases: ["ndjson", "newline-delimited json", "log format"]
tags: ["format", "logging"]
---
Histlog should use NDJSON as its log format so each command event is stored as one structured JSON object per line.

## What

Session logfiles are NDJSON files. Each line contains one complete JSON object representing a command event or related session event, and newline boundaries define record boundaries.

## Why

NDJSON supports append-oriented logging, streaming reads, partial processing, and line-level recovery. It also keeps records human-inspectable while preserving structured fields for Elixir parsing and downstream analysis.

## How

Writers should emit one compact JSON object followed by a newline for each record. Readers should process files line by line, reject or quarantine malformed records, and avoid assuming that the whole logfile must fit in memory.

## Links

- [[Session Logfile Per CLI Session]] - Defines where NDJSON records are written during active CLI sessions.
- [[Daily Finished Session Consolidation]] - Defines the workflow that validates and consumes NDJSON session logs.
- [[Rich Command Metadata Collection]] - Describes the structured fields encoded as NDJSON objects.
- [[Minimal Overhead Constraint]] - Supports NDJSON because append-only line writes keep capture overhead small.
