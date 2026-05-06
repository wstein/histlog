# histlog

histlog is a log-structured, append-only shell history system implemented in Elixir.
It records shell activity as per-session NDJSON event streams and materializes closed sessions into daily files for querying.
It is a short-lived CLI/escript tool, not a daemon or long-running OTP service.

## Development

Useful repository commands:

```sh
make format
make test
make lint
make build
make install
```

The Elixir application lives under `app/`.
`make build` compiles the app and rebuilds `app/histlog`.
`make install` copies that escript to `${PREFIX:-$HOME/.local}/bin/histlog`.

## CLI

Build the escript:

```sh
make build
app/histlog consolidate --root /tmp/histlog --date 2026-05-06
app/histlog query --root /tmp/histlog --date 2026-05-06 --command mix
app/histlog import app/test/fixtures/import/zsh_history --root /tmp/histlog --date 2026-05-06 --source zsh_history
eval "$(app/histlog init zsh)"
```

## Documentation

The repository includes an Antora documentation site under `docs/`:

- `onboarding`: first steps and contributor orientation
- `manual`: operator workflows and command reference
- `architecture`: arc42-based system design, including the v1 specification

## Notes

Durable project knowledge lives in `notes/`.
Run `cx` note checks before architecture-heavy changes when the local tool is available.
