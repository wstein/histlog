# histlog Documentation

This directory contains the Antora documentation site for histlog.

## Structure

- `antora.yml`: component descriptor
- `modules/ROOT`: shared navigation and docs index
- `modules/onboarding`: contributor and operator entrypoint
- `modules/manual`: task-oriented operating guidance
- `modules/architecture`: arc42-based architecture spine and v1 specification

## Workflow

1. Keep high-level project orientation in `onboarding`.
2. Put repeatable commands and operational checks in `manual`.
3. Use the arc42 chapters in `architecture` for system design and tradeoffs.
4. Keep durable, graph-shaped reasoning in `notes/` and promote it into docs when it becomes part of the reader-facing contract.
