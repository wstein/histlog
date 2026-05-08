defmodule Histlog.CLI.Commands.Help do
  @moduledoc false

  alias Histlog.CLI.Commands

  def run([]), do: write_top_level()
  def run(["--all"]), do: write_top_level()
  def run(["query"]), do: Commands.Query.run(["--help"])
  def run(["commands"]), do: Commands.Commands.run(["--help"])
  def run(["stats"]), do: Commands.Stats.run(["--help"])
  def run(["paths"]), do: Commands.Paths.run(["--help"])
  def run(["sessions"]), do: Commands.Sessions.run(["--help"])
  def run(["sync"]), do: Commands.Sync.run(["--help"])
  def run(["rebuild"]), do: Commands.Rebuild.run(["--help"])
  def run(["export"]), do: Commands.Export.run(["--help"])
  def run(["import"]), do: Commands.Import.run(["--help"])
  def run(["init"]), do: Commands.Init.run(["--help"])
  def run(["info"]), do: Commands.Info.run(["--help"])
  def run(["doctor"]), do: Commands.Doctor.run(["--help"])
  def run(["help"]), do: write_top_level()
  def run([command]), do: {:error, "no command-specific help for #{inspect(command)}"}
  def run(args), do: {:error, "unexpected help arguments #{inspect(args)}"}

  defp write_top_level do
    IO.puts("""
    Usage: histlog <command> [options]

    Available commands:
      query       - Flexible query of command history
      commands    - Summarize command usage
      paths       - Show tracked file/directory paths and usage counts
      sessions    - List and inspect recorded shell sessions
      stats       - Show high-level history statistics
      sync        - Materialize closed session logs
      rebuild     - Rebuild the derived database projection
      init        - Print shell integration snippets
      import      - Import shell history files
      export      - Export derived rows for pipelines
      info        - Show runtime paths and environment
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
