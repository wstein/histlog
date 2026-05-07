defmodule Histlog.CLI.Commands.Consolidate do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Consolidator

  @switches Options.common_switches() ++ [rebuild: :boolean, help: :boolean]
  @aliases Options.common_aliases() ++ [h: :help]

  def run(argv) do
    with {:ok, opts, []} <- Options.parse(argv, @switches, @aliases) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        run_consolidate(opts)
      end
    end
  end

  defp run_consolidate(opts) do
    with {:ok, opts} <- Options.normalize(opts) do
      case Consolidator.consolidate(opts) do
        {:ok, manifest} -> IO.puts(JSON.encode!(manifest))
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  defp help do
    """
    Usage: histlog consolidate [options]

    Materialize closed shell sessions for querying.

    Options:
      -h, --help              Show this help
      -d, --date YYYY-MM-DD   Consolidate one date
      -r, --root PATH         Use a specific histlog data root
          --rebuild           Rebuild daily materializations for the date
    """
  end
end
