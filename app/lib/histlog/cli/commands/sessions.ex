defmodule Histlog.CLI.Commands.Sessions do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Query
  alias Histlog.Query.Filter
  alias Histlog.Query.Sessions

  @switches Options.common_switches() ++
              Options.time_switches() ++
              [
                limit: :integer,
                details: :boolean,
                json: :boolean,
                help: :boolean
              ]

  @aliases Options.common_aliases() ++ [h: :help, l: :limit, d: :details]

  def run(argv) do
    with {:ok, opts, args} <- Options.parse(argv, @switches, @aliases),
         {:ok, nil} <- Options.one_optional_arg(args) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        run_sessions(opts)
      end
    end
  end

  defp run_sessions(opts) do
    with {:ok, opts} <- Options.normalize(opts),
         {:ok, rows} <- Query.executions(Keyword.take(opts, [:root, :date])) do
      rows
      |> Filter.rows([], time_filter_opts(opts))
      |> Sessions.rows()
      |> limit_rows(Keyword.get(opts, :limit))
      |> write_rows(output_format(opts), Keyword.get(opts, :details, false))
    end
  end

  defp limit_rows(rows, nil), do: rows
  defp limit_rows(rows, limit) when limit < 0, do: Enum.take(rows, abs(limit))

  defp limit_rows(rows, limit) do
    rows
    |> Enum.take(-limit)
  end

  defp write_rows([], _format, _details?) do
    IO.puts("No sessions recorded.")
    :ok
  end

  defp write_rows(rows, "json", _details?) do
    rows
    |> Enum.map(&Map.drop(&1, [:sample_commands]))
    |> JSON.encode!()
    |> IO.puts()

    :ok
  end

  defp write_rows(rows, "table", details?) do
    IO.write(
      color("Sess", "38;5;141") <>
        " " <>
        color("Start", "38;5;14") <>
        "               " <>
        color("End", "38;5;14") <>
        "                 " <>
        color("Duration", "33") <>
        " " <>
        color("Cmds", "38;5;80") <>
        " Shell Path\n"
    )

    IO.write("--------------------------------------------------------------------------------\n")

    Enum.each(rows, fn row ->
      IO.write(
        color(row.session, "38;5;141") <>
          " " <>
          color(row.start, "38;5;14") <>
          " " <>
          color(row.end, "38;5;14") <>
          " " <>
          color(row.duration |> String.pad_leading(8), "33") <>
          " " <>
          color(row.commands |> Integer.to_string() |> String.pad_leading(4), "38;5;80") <>
          " " <>
          row.shell <>
          " " <>
          row.path <>
          "\n"
      )
    end)

    if details?, do: write_details(rows)

    :ok
  end

  defp write_details(rows) do
    Enum.each(rows, fn row ->
      IO.write("\nSession #{row.session} sample commands:\n")

      Enum.each(
        row.sample_commands,
        &IO.write("  #{String.replace(to_string(&1), "\n", "\\n")}\n")
      )
    end)
  end

  defp output_format(opts) do
    if Keyword.get(opts, :json, false), do: "json", else: "table"
  end

  defp time_filter_opts(opts),
    do: Keyword.take(opts, [:time, :since, :before, :today, :yesterday, :week])

  defp color(text, code), do: "\e[#{code}m#{text}\e[0m"

  defp help do
    """
    Usage: histlog sessions [options]

    List and inspect recorded shell sessions.

    Shows session statistics including command count, start/end times,
    duration, shell, and working directory for each shell session.

    Options:
      -h, --help       Show this help
      -l, --limit N    Maximum sessions to show. Negative N returns earliest N
      -d, --details    Show sample commands for each listed session
          --date DATE  Show sessions for one date
          --today      Show sessions from today
          --yesterday  Show sessions from yesterday
          --week       Show sessions from this week
          --since TIME Show sessions since a time
          --before TIME Show sessions before a time
          --time TIME  Show sessions in a time range
          --root PATH  Use a specific histlog data root
          --json       Output JSON with full metadata
    """
  end
end
