defmodule Histlog.CLI.Commands.Query do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Query

  @switches Options.common_switches() ++
              [
                command: :string,
                cwd: :string,
                exit_status: :integer
              ]

  @aliases Options.common_aliases() ++ [c: :command]

  def run(argv) do
    with {:ok, opts, []} <- Options.parse(argv, @switches, @aliases),
         {:ok, opts} <- Options.normalize(opts) do
      {filters, query_opts} = query_options(opts)

      {:ok, rows} = Query.executions(Keyword.put(query_opts, :filters, filters))
      Enum.each(rows, &IO.write(JSON.encode!(&1) <> "\n"))
      :ok
    end
  end

  defp query_options(opts) do
    filters =
      opts
      |> Keyword.take([:command, :cwd, :exit_status])
      |> Map.new()

    {filters, Keyword.drop(opts, [:command, :cwd, :exit_status])}
  end
end
