defmodule Histlog.CLI.Commands.Help do
  @moduledoc false

  def run(_argv) do
    IO.puts("""
    histlog commands:
      histlog consolidate [--root PATH] [--date YYYY-MM-DD]
      histlog verify [--root PATH] [--date YYYY-MM-DD]
      histlog query [--root PATH] [--date YYYY-MM-DD] [--command TEXT] [--cwd PATH] [--exit-status N]
      histlog tail [--root PATH] [--date YYYY-MM-DD] [--count N]
      histlog import FILE [--root PATH] [--date YYYY-MM-DD] [--source zsh_history|bash_history|fish_history|ndjson]
      histlog hook session-start|preexec|precmd|session-end
      histlog init [zsh|bash|fish] [--aliases]
      histlog completions [zsh|bash|fish]
      histlog doctor [zsh|bash|fish]
    """)

    :ok
  end
end
