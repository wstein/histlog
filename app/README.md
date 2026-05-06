# histlog

histlog is a log-structured, append-only shell history system implemented in Elixir.
It stores canonical shell activity as per-session NDJSON event streams and materializes closed sessions into daily files for querying.

## Development

Run the formatter and tests from this directory:

```sh
mix format
mix test
mix compile --warnings-as-errors
```

## CLI

The Mix project exposes an escript entrypoint:

```sh
mix escript.build
./histlog consolidate --root /tmp/histlog --date 2026-05-06
./histlog query --root /tmp/histlog --date 2026-05-06 --command mix
./histlog tail --root /tmp/histlog --date 2026-05-06 --count 10
./histlog import test/fixtures/import/zsh_history --root /tmp/histlog --date 2026-05-06 --source zsh_history
```

All command surfaces preserve the v1 boundary rule: canonical data crosses subsystem boundaries as NDJSON files.
