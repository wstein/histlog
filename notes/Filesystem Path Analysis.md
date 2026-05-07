---
id: 20260506220914
aliases: ["path analysis", "filesystem analysis"]
tags: ["filesystem", "analysis"]
---
Histlog should analyze filesystem paths so command records can be understood in relation to the files, directories, and repositories they touched.

## What

Filesystem path analysis interprets command context through paths such as the current working directory, explicit file arguments, repository roots, generated artifacts, and other location signals that clarify what a command acted on.

## Why

Shell commands often derive meaning from location. The same command can have very different consequences in a different directory or repository, so path-aware analysis is central to reconstructing intent and impact.

## How

Path analysis should normalize and classify paths without assuming that every string is a filesystem reference. `histlog paths` summarizes observed working directories as execution counts and materialized command argument paths as argument counts.

Closed sessions and imports derive command argument path facts during SQLite materialization. Live session rows derive the same shape at query time until the session closes. Path analysis records the original argument, resolved path, argument position, existence flag, and coarse path type so later query behavior can explain whether a path was observed directly, inferred from a relative argument, or missing at materialization time.

## Links

- [[Histlog Product Purpose]] - Establishes why filesystem context is a first-class product concern.
- [[Rich Command Metadata Collection]] - Supplies the structured records that path analysis enriches.
- [[Minimal Overhead Constraint]] - Bounds path inspection so command capture remains lightweight.
