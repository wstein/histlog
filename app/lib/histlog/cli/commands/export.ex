defmodule Histlog.CLI.Commands.Export do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Query.Filter

  @switches Options.common_switches() ++
              Options.time_switches() ++
              [
                format: :string,
                help: :boolean
              ]

  @aliases Options.common_aliases() ++ [h: :help]

  def run(argv) do
    with {:ok, opts, args} <- Options.parse(argv, @switches, @aliases) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        export(opts, args)
      end
    end
  end

  defp export(opts, []) do
    with {:ok, opts} <- Options.normalize(opts),
         :ok <- validate_format(Keyword.get(opts, :format, "ndjson")),
         {:ok, rows} <- Histlog.Query.executions(Keyword.take(opts, [:root, :date])) do
      rows
      |> Filter.rows([], time_filter_opts(opts))
      |> Enum.each(&IO.write(JSON.encode!(&1) <> "\n"))

      :ok
    end
  end

  defp export(_opts, args), do: {:error, "unexpected export arguments #{inspect(args)}"}

  defp validate_format("ndjson"), do: :ok
  defp validate_format(format), do: {:error, "unsupported export format #{inspect(format)}"}

  defp time_filter_opts(opts),
    do: Keyword.take(opts, [:time, :since, :before, :today, :yesterday, :week])

  defp help do
    """
    Usage: histlog export [--format ndjson] [--root PATH] [--date YYYY-MM-DD]

    Export derived query rows as NDJSON for pipelines and migrations.
    NDJSON is intentionally available through export, not query.

    Time options:
      --today
      --yesterday
      --week
      --since TIME
      --before TIME
      --time TIME
    """
  end
end
