---
id: 20260506222907
aliases: ["execution_observed", "observed execution"]
tags: ["event-model", "execution"]
---
Histlog should use `execution_observed` as the primary execution event because shell completion data may be partial or missing.

## What

An `execution_observed` event records command and cwd identifiers, an event `timestamp`, available duration, available exit status, and a completeness value. It can represent complete, partial, or imported execution evidence without requiring a perfect start and finish pair.

## Why

Interactive shells are unreliable instrumentation surfaces. Hooks may fail, shells may crash, async jobs may detach, and finish data may be unavailable. A single observed event preserves the best available truth without inventing missing lifecycle certainty.

## How

Prefer `execution_observed` in the live stream. For complete executions, use `timestamp` as command start time and `duration_ms` as elapsed time. Avoid redundant `started_at`, `ended_at`, and `recorded_at` fields in canonical session logs.

## Links

- [[Session Logfile Per CLI Session]] - Stores observed executions in the per-session event stream.
- [[Daily Finished Session Consolidation]] - Normalizes observed events into derived execution rows.
- [[Rich Command Metadata Collection]] - Explains why partial command evidence still has value.
