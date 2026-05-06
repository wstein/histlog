defmodule Histlog.CLI.Commands.Consolidate do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Consolidator

  def run(argv) do
    with {:ok, opts, []} <-
           Options.parse(argv, Options.common_switches(), Options.common_aliases()),
         {:ok, opts} <- Options.normalize(opts) do
      case Consolidator.consolidate(opts) do
        {:ok, manifest} ->
          IO.puts(JSON.encode!(manifest))
          :ok

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end
end
