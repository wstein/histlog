defmodule Histlog.CLI.Commands.Commands do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Query
  alias Histlog.Query.Commands

  @switches Options.common_switches() ++
              [
                regex: :boolean,
                fuzzy: :boolean,
                session: :string,
                dir: :string,
                sort_by: :string,
                context: :boolean,
                asc: :boolean,
                desc: :boolean,
                limit: :integer,
                json: :boolean,
                plain: :boolean,
                help: :boolean
              ]

  @aliases Options.common_aliases() ++ [h: :help, l: :limit]
  @sort_values ["recent", "count", "alpha", "context"]

  def run(argv) do
    with {:ok, opts, args} <- Options.parse(argv, @switches, @aliases) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        run_commands(opts, Enum.join(args, " "))
      end
    end
  end

  defp run_commands(opts, search) do
    with {:ok, opts} <- Options.normalize(opts),
         {:ok, opts} <- normalize_command_options(opts, search),
         {:ok, rows} <- Query.executions(Keyword.take(opts, [:root, :date])),
         {:ok, summaries} <- Commands.rows(rows, Keyword.put(opts, :search, search)) do
      write_rows(summaries, output_format(opts))
    end
  end

  defp normalize_command_options(opts, search) do
    opts =
      if Keyword.get(opts, :context, false) do
        Keyword.put(opts, :sort_by, "context")
      else
        opts
      end

    sort_by = Keyword.get(opts, :sort_by, "recent")

    if sort_by in @sort_values do
      validate_regex_option(opts, search)
    else
      {:error, "unsupported commands sort #{inspect(sort_by)}"}
    end
  end

  defp validate_regex_option(opts, search) do
    if Keyword.get(opts, :regex, false) && search != "" do
      case Regex.compile(search) do
        {:ok, _regex} -> {:ok, opts}
        {:error, {reason, position}} -> {:error, "invalid regex at #{position}: #{reason}"}
        {:error, reason} -> {:error, "invalid regex: #{inspect(reason)}"}
      end
    else
      {:ok, opts}
    end
  end

  defp output_format(opts) do
    cond do
      Keyword.get(opts, :json, false) -> "json"
      Keyword.get(opts, :plain, false) -> "plain"
      true -> "table"
    end
  end

  defp write_rows(rows, "json") do
    rows
    |> JSON.encode!()
    |> IO.puts()

    :ok
  end

  defp write_rows(rows, "plain") do
    Enum.each(rows, &IO.write(&1.command <> "\n"))
    :ok
  end

  defp write_rows([], "table") do
    IO.puts("No commands recorded.")
    :ok
  end

  defp write_rows(rows, "table") do
    IO.write(
      color("Count", "38;5;80") <>
        " " <>
        color("Last Used", "38;5;14") <>
        "           " <>
        color("Ok", "38;5;84") <>
        " " <>
        color("Fail", "38;5;203") <>
        " Command\n"
    )

    IO.write("-------------------------------------------------------------\n")

    Enum.each(rows, fn row ->
      IO.write(
        color(row.count |> Integer.to_string() |> String.pad_leading(5), "38;5;80") <>
          " " <>
          color(format_timestamp(row.last_seen), "38;5;14") <>
          " " <>
          color(row.successes |> Integer.to_string() |> String.pad_leading(4), "38;5;84") <>
          " " <>
          color(row.failures |> Integer.to_string() |> String.pad_leading(4), "38;5;203") <>
          " " <>
          row.command <>
          "\n"
      )
    end)

    :ok
  end

  defp format_timestamp(nil), do: String.pad_trailing("-", 19)

  defp format_timestamp(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} ->
        datetime
        |> DateTime.to_unix(:second)
        |> :calendar.system_time_to_local_time(:second)
        |> then(fn {{year, month, day}, {hour, minute, second}} ->
          "#{pad(year, 4)}-#{pad(month, 2)}-#{pad(day, 2)} #{pad(hour, 2)}:#{pad(minute, 2)}:#{pad(second, 2)}"
        end)

      {:error, _reason} ->
        "-"
    end
    |> String.pad_trailing(19)
  end

  defp pad(value, count), do: value |> Integer.to_string() |> String.pad_leading(count, "0")

  defp color(text, code), do: "\e[#{code}m#{text}\e[0m"

  defp help do
    """
    Usage: histlog commands [search] [options]

    Summarize command usage across materialized history and live sessions.

    Options:
      -h, --help             Show this help
      -l, --limit N          Maximum commands to show
          --date DATE        Summarize one date
          --root PATH        Use a specific histlog data root
          --regex            Treat search as a regular expression
          --fuzzy            Fuzzy-match search against command text
          --session ID       Restrict to one session
          --dir PATH         Restrict to one working directory
          --sort-by FIELD    recent, count, alpha, or context
          --context          Sort by session/directory spread, then count
          --asc              Sort ascending
          --desc             Sort descending
          --json             Output JSON
          --plain            Output only command text, one per line
    """
  end
end
