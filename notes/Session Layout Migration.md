---
id: 20260508103000
aliases: ["flatten session layout", "dated session directory migration"]
tags: ["migration", "sessions", "maintenance"]
---
Early alpha session files can be moved from dated directories into the flat session layout with a standalone maintenance script.

## Decision

Do not keep legacy dated session-directory support in the main query or consolidation paths.
Keep the cleanup path under `scripts/flatten-session-layout.exs` so the application storage model stays simple.

## Behavior

The script moves:

```text
sessions/live/YYYY-MM-DD/session-*.ndjson
sessions/closed/YYYY-MM-DD/session-*.ndjson
sessions/quarantine/YYYY-MM-DD/session-*.ndjson
```

to:

```text
sessions/live/session-YYYY-MM-DD-*.ndjson
sessions/closed/session-YYYY-MM-DD-*.ndjson
sessions/quarantine/session-YYYY-MM-DD-*.ndjson
```

It supports `--dry-run`, refuses conflicting overwrites, and removes only empty legacy date directories after successful moves.

## Links

- [[Session Logfile Per CLI Session]] - Defines the flat session logfile layout.
- [[Query Source Union]] - Keeps query-family commands on SQLite plus flat live session files.
