---
id: 20260506221343
aliases: ["jsonl", "log format"]
tags: ["format", "logging"]
---
Histlog should use JSONL as its log format so each command event is stored as one structured JSON object per line.

## What

Session logfiles are JSONL files. Each line contains one complete JSON object representing a command event or related session event, and newline boundaries define record boundaries.

## Why

JSONL supports append-oriented logging, streaming reads, partial processing, and line-level recovery. It also keeps records human-inspectable while preserving structured fields for Elixir parsing and downstream analysis.

## How

Writers should emit one compact JSON object followed by a newline for each record. Readers should process files line by line, reject or quarantine malformed records, and avoid assuming that the whole logfile must fit in memory.

## Links

- [[Session Logfile Per CLI Session]] - Defines where JSONL records are written during active CLI sessions.
- [[Daily Finished Session Consolidation]] - Defines the workflow that validates and consumes JSONL session logs.
- [[Rich Command Metadata Collection]] - Describes the structured fields encoded as JSONL objects.
- [[Minimal Overhead Constraint]] - Supports JSONL because append-only line writes keep capture overhead small.
