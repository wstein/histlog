---
id: 20260506224844
aliases: ["histlog init", "shell init"]
tags: ["shell", "integration"]
---
`histlog init [SHELL]` should print shell-native integration code and must never silently edit shell rc files.

## What

Users opt in by evaluating the printed script, such as `eval "$(histlog init zsh)"` or `histlog init fish | source`. The command may auto-detect the shell, but explicit shell names are preferred in persistent setup files.

## Why

Shell rc files are personal, fragile, and security-sensitive. Printing integration code keeps installation reversible, reviewable, and compatible with users who manage dotfiles declaratively.

## How

Implement `init` as stdout-only generation for supported shells. Include completion setup by default. Add aliases only when the user passes `--aliases`, because aliases change the interactive command namespace.

## Links

- [[Shell Hook CLI Boundary]] - Defines the runtime commands printed shell code must call.
- [[Redaction Before Persistence]] - Keeps the trusted persistence logic on the Elixir side.
- [[Minimal Overhead Constraint]] - Explains why generated shell code must stay thin.
