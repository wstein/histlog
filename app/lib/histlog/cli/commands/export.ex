defmodule Histlog.CLI.Commands.Export do
  @moduledoc false

  alias Histlog.CLI.Options

  @switches Options.common_switches() ++
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
      Enum.each(rows, &IO.write(JSON.encode!(&1) <> "\n"))
      :ok
    end
  end

  defp export(_opts, args), do: {:error, "unexpected export arguments #{inspect(args)}"}

  defp validate_format("ndjson"), do: :ok
  defp validate_format(format), do: {:error, "unsupported export format #{inspect(format)}"}

  defp help do
    """
    Usage: histlog export [--format ndjson] [--root PATH] [--date YYYY-MM-DD]

    Export derived execution rows as NDJSON for pipelines and migrations.
    NDJSON is intentionally available through export, not query.
    """
  end
end
