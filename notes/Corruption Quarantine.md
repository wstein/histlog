---
id: 20260506222909
aliases: ["quarantine", "corrupt session"]
tags: ["integrity", "failure-mode"]
---
Histlog should quarantine malformed session files so one corrupt stream cannot block consolidation for the rest of the day.

## What

When a session file cannot be parsed or fails schema or sequence validation, consolidation moves or copies it to a quarantine area and records the failure in the manifest. Other valid sessions continue processing.

## Why

Users may edit files, sync tools may conflict, and crashes may leave incomplete records. Session-level isolation keeps failure blast radius small and preserves the bad input for later inspection.

## How

Treat parse failure, invalid event shape, sequence gaps, and inconsistent session identity as quarantine reasons. Never silently drop malformed input; record enough reason text for operators and tests to diagnose the failure.

## Links

- [[Session Logfile Per CLI Session]] - Gives corruption a session-sized containment boundary.
- [[Manifest And Checkpointing]] - Records quarantined sessions in daily metadata.
- [[Daily Finished Session Consolidation]] - Applies quarantine while materializing closed sessions.
