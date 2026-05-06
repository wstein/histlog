---
id: 20260506222910
aliases: ["session identity", "pid reuse"]
tags: ["identity", "integrity"]
---
Histlog session identity should combine opaque IDs with process and start metadata so PID reuse cannot confuse liveness or consolidation.

## What

Each session records an opaque `session_id`, host, process id, parent process id, timestamp, monotonic start value, and shell name in the `session_started` header. Filenames may include host, pid, and start nanoseconds for operator readability.

## Why

PIDs can be reused, clocks can shift, and host-local sessions can overlap. Robust identity prevents active, closed, stale, and imported sessions from being misclassified.

## How

Use `session_id` as the primary identity for the session file, not as repeated payload on every event. Later rows inherit identity from the one-file-per-session boundary.

## Links

- [[Session Logfile Per CLI Session]] - Defines one file per session.
- [[Daily Finished Session Consolidation]] - Relies on identity to avoid duplicate processing.
- [[Corruption Quarantine]] - Treats inconsistent identity as a validation failure.
