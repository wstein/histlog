# histlog

histlog is a log-structured, append-only shell history system implemented in Elixir.
It stores canonical shell activity as compact per-session NDJSON event streams and materializes closed sessions into daily files for querying.
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
./histlog consolidate --root /tmp/histlog --date 2026-05-06 --rebuild
./histlog verify --root /tmp/histlog --date 2026-05-06
./histlog query --root /tmp/histlog --date 2026-05-06 --command mix
./histlog query --root /tmp/histlog --date 2026-05-06 --command mix --json
./histlog paths --root /tmp/histlog --date 2026-05-06
./histlog sessions --root /tmp/histlog --date 2026-05-06 --details
./histlog import test/fixtures/import/zsh_history --root /tmp/histlog --date 2026-05-06 --source zsh_history
./histlog init zsh
./histlog init zsh --binary /absolute/path/to/histlog
./histlog doctor zsh --plain
```

Shell integration is opt-in: `histlog init` prints shell-native setup code and never edits shell rc files.
Supported v1 shells are zsh, bash, and fish.
