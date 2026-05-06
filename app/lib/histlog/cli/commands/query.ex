defmodule Histlog.CLI.Commands.Query do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Query

  @switches Options.common_switches() ++
              [
                command: :string,
                cwd: :string,
                exit_status: :integer,
                format: :string
              ]

  @aliases Options.common_aliases() ++ [c: :command]

  def run(argv) do
    with {:ok, opts, []} <- Options.parse(argv, @switches, @aliases),
         {:ok, opts} <- Options.normalize(opts) do
      {filters, query_opts} = query_options(opts)

      {:ok, rows} = Query.executions(Keyword.put(query_opts, :filters, filters))

      case write_rows(rows, Keyword.get(opts, :format, "table")) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp write_rows(rows, "table") do
    rows
    |> table_lines()
    |> Enum.each(&IO.write(&1 <> "\n"))

    :ok
  end

  defp write_rows(rows, "ndjson") do
    Enum.each(rows, &IO.write(JSON.encode!(&1) <> "\n"))

    :ok
  end

  defp write_rows(_rows, format), do: {:error, "unsupported query format #{inspect(format)}"}

  defp table_lines(rows) do
    labels = session_labels(rows)

    [
      "Sess Timestamp             Duration Exit Command",
      "--------------------------------------------------"
      | Enum.map(rows, &table_row(&1, labels))
    ]
  end

  defp table_row(row, labels) do
    session = Map.fetch!(labels, row["session_id"])
    timestamp = format_timestamp(row["timestamp"])
    duration = format_duration(row["duration_ms"])
    exit = format_exit(row["exit_status"])
    command = row["command"] |> to_string() |> String.replace("\n", "\\n")

    "#{session} #{timestamp} #{duration} #{exit} #{command}"
  end

  defp session_labels(rows) do
    rows
    |> Enum.map(& &1["session_id"])
    |> Enum.uniq()
    |> Enum.with_index(1)
    |> Map.new(fn {session_id, index} ->
      {session_id, index |> Integer.to_string() |> String.pad_leading(4, "0")}
    end)
  end

  defp format_timestamp(nil), do: String.pad_trailing("?", 19)

  defp format_timestamp(timestamp) do
    timestamp
    |> to_string()
    |> String.replace("T", " ")
    |> String.replace_suffix("Z", "")
    |> String.slice(0, 19)
    |> String.pad_trailing(19)
  end

  defp format_duration(nil), do: String.pad_leading("?", 9)

  defp format_duration(duration_ms) do
    seconds =
      duration_ms
      |> Kernel./(1000)
      |> :erlang.float_to_binary(decimals: 3)

    String.pad_leading("#{seconds}s", 9)
  end

  defp format_exit(nil), do: String.pad_trailing("?", 4)
  defp format_exit(0), do: String.pad_trailing("✓", 4)
  defp format_exit(status), do: "✗#{status}" |> String.slice(0, 4) |> String.pad_trailing(4)

  defp query_options(opts) do
    filters =
      opts
      |> Keyword.take([:command, :cwd, :exit_status])
      |> Map.new()

    {filters, Keyword.drop(opts, [:command, :cwd, :exit_status, :format])}
  end
end
