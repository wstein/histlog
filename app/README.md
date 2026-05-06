# histlog

histlog is a log-structured, append-only shell history system implemented in Elixir.
It stores canonical shell activity as per-session NDJSON event streams and materializes closed sessions into daily files for querying.
The application is packaged as a short-lived escript CLI, not a daemon or long-running OTP service.

## Development

Run the formatter and tests from this directory:

```sh
mix format
mix test
mix compile --warnings-as-errors
mix escript.build
```

## CLI

The Mix project exposes an escript entrypoint:

```sh
mix escript.build
./histlog consolidate --root /tmp/histlog --date 2026-05-06
./histlog query --root /tmp/histlog --date 2026-05-06 --command mix
./histlog query --root /tmp/histlog --date 2026-05-06 --command mix --json
./histlog paths --root /tmp/histlog --date 2026-05-06
./histlog tail --root /tmp/histlog --date 2026-05-06 --count 10
./histlog import test/fixtures/import/zsh_history --root /tmp/histlog --date 2026-05-06 --source zsh_history
./histlog init zsh
./histlog completions fish
./histlog doctor zsh
```

All command surfaces preserve the v1 boundary rule: canonical data crosses subsystem boundaries as NDJSON files.
