---
id: 20260507143100
aliases: ["homebrew automation", "tap automation"]
tags: ["release", "automation", "homebrew"]
---
The source repository owns Homebrew publishing.
The tap repository receives generated formula commits.

## What

The release workflow builds the launcher bundle, uploads it to the GitHub release, generates `Formula/histlog.rb`, and pushes the formula to `wstein/homebrew-tap`.

## Invariant

The formula SHA is computed from the same GitHub release tarball uploaded by the release workflow.

## Requirements

- release tag `vX.Y.Z` or `vX.Y.Z-alpha.N`
- `app/mix.exs` version matching the tag without `v`
- release commit contained in `origin/develop`
- green develop CI for the tagged commit
- `HOMEBREW_TAP_PUSH_TOKEN` in the `homebrew` GitHub environment

## Links

- [[Homebrew Tap]] - Describes the install-facing tap model.
- [[Daily Rebuild Verification]] - Explains why formula tests must run SQLite-backed commands.
