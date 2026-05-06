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

## Links

- [[Daily Finished Session Consolidation]] - Produces daily manifests as part of materialization.
- [[NDJSON Boundary Contract]] - Keeps checkpointing at the file boundary.
- [[Minimal Overhead Constraint]] - Allows checkpoint work outside the interactive shell path.
