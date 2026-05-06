---
id: 20260506221340
aliases: ["session logfile", "cli session log"]
tags: ["logging", "session"]
---
Histlog should create one logfile for each CLI session so active command capture is isolated by session before later consolidation.

## What

Each CLI session writes to its own append-oriented logfile. The session logfile is the live capture artifact for commands observed during that session, and it should remain distinct from consolidated backlog data until the session is finished.

## Why

Per-session logs reduce write contention, make active sessions easier to reason about, and preserve session-local context. They also let consolidation operate only on finished sessions instead of racing with currently active shell activity.

## How

Name and locate session logfiles so a later process can distinguish active, finished, and already consolidated sessions. Do not mix multiple CLI sessions into one live logfile; use consolidation to merge or index finished session data into the backlog.

## Links

- [[Elixir Implementation Language]] - Defines the runtime expected to manage session logfile behavior.
- [[JSONL Log Format]] - Defines the record format inside each session logfile.
- [[Daily Finished Session Consolidation]] - Moves finished session logfiles into durable backlog storage.
- [[Rich Command Metadata Collection]] - Describes the records written into session logfiles.
