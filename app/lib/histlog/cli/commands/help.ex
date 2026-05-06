defmodule Histlog.CLI.Commands.Help do
  @moduledoc false

  alias Histlog.CLI.Commands

  def run([]), do: write_top_level()
  def run(["--all"]), do: write_top_level()
  def run(["query"]), do: Commands.Query.run(["--help"])
  def run(["paths"]), do: Commands.Paths.run(["--help"])
  def run(["sessions"]), do: Commands.Sessions.run(["--help"])
  def run(["help"]), do: write_top_level()
  def run([command]), do: {:error, "no command-specific help for #{inspect(command)}"}
  def run(args), do: {:error, "unexpected help arguments #{inspect(args)}"}

  defp write_top_level do
    IO.puts("""
    Usage: histlog <command> [options]

    Available commands:
      query       - Flexible query of command history
      sessions    - List and inspect recorded shell sessions
      paths       - Show tracked file/directory paths and usage counts
      consolidate - Materialize closed session logs
      verify      - Verify daily materialization checksums
      import      - Import shell history files
      init        - Print shell integration snippets
      doctor      - Diagnose setup
      help        - Show this help

    Global flags:
      -h, --help        Show top-level help
      --help-all        Show full help

    For command-specific help run:
      histlog <command> --help
      histlog help <command>
    """)

    :ok
  end
end
