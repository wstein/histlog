# histlog

histlog is a shell history tool for recording, searching, and reviewing the commands you run.

It helps you answer questions like:

- What did I run earlier today?
- Which commands failed?
- What did I run in this project?
- Which directories and sessions have I been working in?

## Install

From this repository:

```sh
make build
make install
```

Make sure `~/.local/bin` is on your `PATH`.

## Enable

Add the matching line to your shell config:

```sh
eval "$(histlog init zsh)"
eval "$(histlog init bash)"
```

For fish:

```fish
histlog init fish | source
```

## Use

```sh
histlog query
histlog query mix
histlog query --today --failed
histlog query --command git --plain
```

More query examples:

```sh
histlog query --today
histlog query --yesterday
histlog query --week
histlog query --success
histlog query --failed
histlog query --dir .
histlog query --slow
histlog query --duration '>10s'
histlog query --regex 'git (commit|push)'
histlog query --json
histlog query --limit 20
```

```sh
histlog sessions
histlog paths
histlog doctor zsh --plain
```

Import existing history:

```sh
histlog import ~/.zsh_history --source zsh_history
histlog import ~/.bash_history --source bash_history
```

## Docs

More documentation lives in `docs/`.
