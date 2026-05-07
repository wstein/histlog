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

Writers should emit one compact JSON object followed by a newline for each record. Readers should process files line by line and avoid assuming that the whole logfile must fit in memory. Consolidation rejects or quarantines malformed session records; query-oriented readers skip malformed materialized or live rows with a warning so one bad line does not prevent access to valid history.

Validation happens at both event and session scope. Single events must have parseable timestamps and valid domain fields; complete session streams must have a `session_started` header, gapless sequence numbers, and catalog references that point to earlier definitions in the same file.

Command text is normalized before persistence by trimming leading and trailing whitespace. If a shell marks private commands by a leading space, histlog stores that privacy signal in `is_private` on `command_defined` instead of preserving the leading space in the command text.

The on-disk representation remains compact maps. Internal code may convert those maps to typed event structs when explicit shape helps implementation, but encoding and decoding still happen at the NDJSON boundary.

## Links

- [[Session Logfile Per CLI Session]] - Defines where NDJSON records are written during active CLI sessions.
- [[Daily Finished Session Consolidation]] - Defines the workflow that validates and consumes NDJSON session logs.
- [[Rich Command Metadata Collection]] - Describes the structured fields encoded as NDJSON objects.
- [[Minimal Overhead Constraint]] - Supports NDJSON because append-only line writes keep capture overhead small.
- [[CLI Option Parsing]] - Keeps NDJSON out of query output and routes line-oriented output through export.
