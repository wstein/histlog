---
id: 20260507143000
aliases: ["wstein tap", "homebrew formula"]
tags: ["release", "homebrew"]
---
histlog publishes a Homebrew formula to `wstein/tap`, backed by `wstein/homebrew-tap`.

## What

The formula installs the supported launcher artifact, not the plain escript alone.
SQLite-backed workflows require the compiled `exqlite` NIF tree, so the release tarball contains:

- `histlog`
- `histlog.escript`
- `lib/`

## Why

Dogfooding proved that a plain escript can print help but cannot reliably load `exqlite` for database commands.
Homebrew must install the launcher bundle so `histlog consolidate` and `histlog doctor` database checks work after installation.

## Links

- [[Homebrew Tap Automation]] - Describes release workflow automation.
- [[No Long Running Service]] - Keeps installed histlog as a short-lived launcher.
