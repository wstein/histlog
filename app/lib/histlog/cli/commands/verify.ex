defmodule Histlog.CLI.Commands.Verify do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Verifier

  @switches Options.common_switches() ++ [help: :boolean]
  @aliases Options.common_aliases() ++ [h: :help]

  def run(argv) do
    with {:ok, opts, []} <- Options.parse(argv, @switches, @aliases) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        run_verify(opts)
      end
    end
  end

  defp run_verify(opts) do
    with {:ok, opts} <- Options.normalize(opts) do
      case Verifier.verify(opts) do
        {:ok, report} ->
          IO.puts(JSON.encode!(report))
          :ok

        {:error, report} when is_map(report) ->
          IO.puts(JSON.encode!(report))
          {:error, "verification failed"}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  defp help do
    """
    Usage: histlog verify [options]

    Verify daily materialization checksums and record counts.

    Options:
      -h, --help              Show this help
      -d, --date YYYY-MM-DD   Verify one date
      -r, --root PATH         Use a specific histlog data root
    """
  end
end
