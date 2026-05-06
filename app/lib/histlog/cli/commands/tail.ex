defmodule Histlog.CLI.Commands.Tail do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Query

  @switches Options.common_switches() ++ [count: :integer]
  @aliases Options.common_aliases()

  def run(argv) do
    with {:ok, opts, []} <- Options.parse(argv, @switches, @aliases),
         {:ok, opts} <- Options.normalize(opts) do
      count = Keyword.get(opts, :count, 10)
      {:ok, rows} = Query.events(opts)

      rows
      |> Enum.take(-count)
      |> Enum.each(&IO.write(JSON.encode!(&1) <> "\n"))

      :ok
    end
  end
end
