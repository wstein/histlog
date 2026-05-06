defmodule Histlog.CLI.Commands.Verify do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Verifier

  def run(argv) do
    with {:ok, opts, []} <-
           Options.parse(argv, Options.common_switches(), Options.common_aliases()),
         {:ok, opts} <- Options.normalize(opts) do
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
end
