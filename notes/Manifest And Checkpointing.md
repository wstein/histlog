---
id: 20260506222908
aliases: ["manifest", "checkpointing"]
tags: ["integrity", "consolidation"]
---
Histlog consolidation should write a manifest for each day so materialization is idempotent and auditable.

## What

A daily manifest records the day, processed sessions, record counts, generated output paths, checksums, and quarantined sessions. It is the checkpoint that prevents reprocessing the same closed session during future consolidation runs.

## Why

Flat-file materialization shifts integrity work into the application. Manifests make this work explicit: operators and tests can see what was processed, what was skipped, and which output checksum represents the materialized day.

## How

Write manifests after successful output materialization. Consolidators should read an existing manifest before processing, skip already processed session files, and produce deterministic manifest content for the same input set.

`histlog verify --date YYYY-MM-DD` recomputes record counts and checksums from the daily materialized files and compares them to the manifest. Verification is read-only; rebuild support is a separate operational workflow.

`histlog consolidate --rebuild --date YYYY-MM-DD` starts from an empty manifest for that date, ignores prior processed-session checkpoints, and rewrites daily materializations from closed session files.

## Links

- [[Daily Finished Session Consolidation]] - Produces daily manifests as part of materialization.
- [[Daily Rebuild Verification]] - Defines read-only verification of materialized daily files.
- [[NDJSON Boundary Contract]] - Keeps checkpointing at the file boundary.
- [[Minimal Overhead Constraint]] - Allows checkpoint work outside the interactive shell path.
