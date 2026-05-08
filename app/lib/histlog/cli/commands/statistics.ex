defmodule Histlog.CLI.Commands.Statistics do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Query
  alias Histlog.Query.Filter
  alias Histlog.Query.Statistics

  @switches Options.common_switches() ++
              Options.time_switches() ++
              [
                top: :integer,
                json: :boolean,
                plain: :boolean,
                help: :boolean
              ]

  @aliases Options.common_aliases() ++ [h: :help]

  def run(argv) do
    with {:ok, opts, args} <- Options.parse(argv, @switches, @aliases),
         {:ok, nil} <- Options.one_optional_arg(args) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        run_statistics(opts)
      end
    end
  end

  defp run_statistics(opts) do
    with {:ok, opts} <- Options.normalize(opts),
         {:ok, rows} <- Query.executions(Keyword.take(opts, [:root, :date])) do
      rows
      |> Filter.rows([], time_filter_opts(opts))
      |> Statistics.summary(top_limit: Keyword.get(opts, :top, 10))
      |> write(output_format(opts))
    end
  end

  defp output_format(opts) do
    cond do
      Keyword.get(opts, :json, false) -> "json"
      Keyword.get(opts, :plain, false) -> "plain"
      true -> "table"
    end
  end

  defp write(summary, "json") do
    summary
    |> JSON.encode!()
    |> IO.puts()

    :ok
  end

  defp write(summary, "plain") do
    IO.puts("total_commands=#{summary.total_commands}")
    IO.puts("unique_commands=#{summary.unique_commands}")
    IO.puts("sessions=#{summary.sessions}")
    IO.puts("failed_commands=#{summary.failed_commands}")
    :ok
  end

  defp write(summary, "table") do
    IO.puts("#{color_label("Commands")}: #{summary.total_commands}")
    IO.puts("#{color_label("Unique")}: #{summary.unique_commands}")
    IO.puts("#{color_label("Sessions")}: #{summary.sessions}")
    IO.puts("#{color_label("Imported")}: #{summary.imported_commands}")
    IO.puts("#{color_label("Live")}: #{summary.live_commands}")

    IO.puts(
      "#{color_label("Successful")}: #{color(Integer.to_string(summary.successful_commands), "38;5;84")}"
    )

    IO.puts(
      "#{color_label("Failed")}: #{color(Integer.to_string(summary.failed_commands), "38;5;203")}"
    )

    IO.puts("#{color_label("First Seen")}: #{summary.first_seen || "-"}")
    IO.puts("#{color_label("Last Seen")}: #{summary.last_seen || "-"}")

    IO.puts("")
    IO.puts(color_label("Top Commands"))

    Enum.each(summary.top_commands, fn row ->
      IO.puts("  #{row.count |> Integer.to_string() |> String.pad_leading(5)}  #{row.command}")
    end)

    IO.puts("")
    IO.puts(color_label("Top Paths"))

    Enum.each(summary.top_paths, fn row ->
      IO.puts(
        "  #{(row.exec + row.args) |> Integer.to_string() |> String.pad_leading(5)}  #{row.path}"
      )
    end)

    :ok
  end

  defp color_label(label), do: color(label, "38;5;14")
  defp color(text, code), do: "\e[#{code}m#{text}\e[0m"

  defp time_filter_opts(opts),
    do: Keyword.take(opts, [:time, :since, :before, :today, :yesterday, :week])

  defp help do
    """
    Usage: histlog statistics [options]

    Show high-level history statistics over materialized history and live sessions.

    Options:
      -h, --help             Show this help
          --date DATE        Summarize one date
          --today            Summarize today
          --yesterday        Summarize yesterday
          --week             Summarize this week
          --since TIME       Summarize commands since a time
          --before TIME      Summarize commands before a time
          --time TIME        Summarize a time range
          --root PATH        Use a specific histlog data root
          --top N            Number of top commands and paths to show
          --json             Output JSON
          --plain            Output key=value lines
    """
  end
end
