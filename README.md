# histlog

Better shell history for people who live in terminals.

Your shell remembers command text. histlog remembers the useful context too: when a command ran, where it ran, whether it succeeded, how long it took, and which session it belonged to.

Use it when you want to find:

- the command you ran in this project yesterday
- the failed deploy/build/test command from earlier today
- the slow commands that ate your afternoon
- the directories you actually worked in
- a clean list of commands to rerun, share, or script

Example:

```text
❯ histlog query
Sess Timestamp           Duration Exit Command
--------------------------------------------------
0001 2026-05-07 09:14:02    0.184s ✓    git status
0001 2026-05-07 09:14:12    5.812s ✓    mix test
0001 2026-05-07 09:15:01    0.038s ✗1   psql histlog_dev
0002 2026-05-07 09:18:44   12.407s ✓    make build
```

## Quick Start

Build and install the CLI:

```sh
make build
make install
```

Enable it in your shell:

```sh
eval "$(histlog init zsh)"
```

For bash:

```sh
eval "$(histlog init bash)"
```

For fish:

```fish
histlog init fish | source
```

Now use your terminal normally.

## Search Your History

Show recent commands:

```sh
histlog query
```

Find commands by text:

```sh
histlog query git
histlog query "mix test"
histlog query --regex 'git (commit|push)'
```

Filter by time:

```sh
histlog query --today
histlog query --yesterday
histlog query --week
```

Find failures and slow commands:

```sh
histlog query --failed
histlog query --success
histlog query --slow
histlog query --duration '>10s'
```

Work with output:

```sh
histlog query --plain
histlog query --json
histlog query --limit 20
```

## Explore Your Work

```sh
histlog sessions
histlog paths
histlog doctor zsh --plain
```

## Import Existing History

```sh
histlog import ~/.zsh_history --source zsh_history
histlog import ~/.bash_history --source bash_history
```

## Notes

histlog never edits your shell config automatically. `histlog init` prints the shell integration snippet so you decide where it goes.

More documentation lives in `docs/`.
