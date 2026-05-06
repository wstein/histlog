# histlog

histlog is an Elixir shell history tool.

It records each shell session into its own append-only log file, then materializes closed sessions into daily history views that are easy to query.

histlog is:

- shell history with command, cwd, duration, exit status, shell, host, and session context
- file-backed and append-only
- a short-lived CLI/escript, not a daemon
- explicit about shell setup: it never silently edits rc files

NDJSON is the internal storage format. The normal CLI is human-facing; use `histlog export --format ndjson` only when you want line-oriented data for another tool.

## Install For Local Use

From this repository:

```sh
make build
make install
```

`make install` links the built escript to:

```sh
~/.local/bin/histlog
```

Make sure `~/.local/bin` is on your `PATH`.

## Enable Shell Capture

Add one of these to your shell config:

```sh
eval "$(histlog init zsh)"
eval "$(histlog init bash)"
```

For fish:

```fish
histlog init fish | source
```

To pin the exact executable used by hooks:

```sh
eval "$(histlog init zsh --binary /absolute/path/to/histlog)"
```

Supported v1 shells are zsh, bash, and fish.

## Use It

Query your history:

```sh
histlog query
histlog query mix
histlog query --today --failed
histlog query --command "git" --plain
```

Inspect sessions and paths:

```sh
histlog sessions
histlog sessions --details
histlog paths
```

Materialize and verify closed sessions:

```sh
histlog consolidate
histlog verify
```

Import existing shell history:

```sh
histlog import ~/.zsh_history --source zsh_history
histlog import ~/.bash_history --source bash_history
```

Export derived rows for pipelines:

```sh
histlog export --format ndjson
```

Diagnose shell setup:

```sh
histlog doctor zsh
histlog doctor zsh --plain
```

## Where Data Lives

By default:

```text
~/.local/share/histlog/
```

Important directories:

```text
sessions/live/      active shell sessions
sessions/closed/    ended shell sessions
daily/              materialized daily views
imports/            imported shell history
manifests/          verification metadata
hook-state/         temporary shell adapter state
```

`hook-state/` is disposable adapter state. Session logs and daily materializations are the durable history.

## More Docs

The full manual and architecture docs live under `docs/`.
Project notes live under `notes/`.
