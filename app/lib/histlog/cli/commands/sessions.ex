defmodule Histlog.CLI.Commands.Sessions do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Query

  @switches Options.common_switches() ++
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
      |> session_rows()
      |> limit_rows(Keyword.get(opts, :limit))
      |> write_rows(output_format(opts), Keyword.get(opts, :details, false))
    end
  end

  defp session_rows(rows) do
    rows
    |> Enum.group_by(&session_key/1)
    |> Enum.map(fn {session_id, commands} ->
      sorted = Enum.sort_by(commands, &(&1["timestamp"] || ""))
      first = List.first(sorted) || %{}
      last = List.last(sorted) || %{}
      start_unix = unix(first["timestamp"])
      end_unix = end_unix(last)

      %{
        session: nil,
        session_id: display_session_id(session_id),
        start: format_timestamp(first["timestamp"]),
        end: format_unix(end_unix),
        duration: format_duration(duration_seconds(start_unix, end_unix)),
        shell: first["shell"] || "-",
        tty: first["tty"] || "-",
        path: first["cwd"] || "-",
        commands: length(commands),
        sample_commands: sorted |> Enum.map(& &1["command"]) |> Enum.take(5)
      }
    end)
    |> Enum.sort_by(& &1.start)
    |> Enum.with_index(1)
    |> Enum.map(fn
      {%{session_id: nil} = row, _index} ->
        %{row | session: "(imported)"}

      {row, index} ->
        %{row | session: index |> Integer.to_string() |> String.pad_leading(4, "0")}
    end)
  end

  defp session_key(%{"session_id" => nil}), do: "(imported)"
  defp session_key(%{"session_id" => session_id}), do: session_id
  defp session_key(_row), do: "(unknown)"

  defp display_session_id("(imported)"), do: nil
  defp display_session_id(session_id), do: session_id

  defp end_unix(row) do
    case {unix(row["timestamp"]), row["duration_ms"]} do
      {nil, _duration} -> nil
      {start, duration} when is_integer(duration) -> start + duration / 1000
      {start, duration} when is_float(duration) -> start + duration / 1000
      {start, _duration} -> start
    end
  end

  defp duration_seconds(nil, _end_unix), do: nil
  defp duration_seconds(_start_unix, nil), do: nil
  defp duration_seconds(start_unix, end_unix), do: max(end_unix - start_unix, 0)

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

  defp format_timestamp(nil), do: String.pad_trailing("-", 19)

  defp format_timestamp(timestamp) do
    timestamp
    |> local_timestamp()
    |> String.pad_trailing(19)
  end

  defp format_unix(nil), do: String.pad_trailing("-", 19)

  defp format_unix(unix) do
    unix
    |> trunc()
    |> :calendar.system_time_to_local_time(:second)
    |> then(fn {{year, month, day}, {hour, minute, second}} ->
      "#{pad(year, 4)}-#{pad(month, 2)}-#{pad(day, 2)} #{pad(hour, 2)}:#{pad(minute, 2)}:#{pad(second, 2)}"
    end)
    |> String.pad_trailing(19)
  end

  defp format_duration(nil), do: "?"

  defp format_duration(seconds) when seconds < 60 do
    :erlang.float_to_binary(seconds / 1, decimals: 3) <> "s"
  end

  defp format_duration(seconds) when seconds < 3600 do
    :erlang.float_to_binary(seconds / 60, decimals: 2) <> "m"
  end

  defp format_duration(seconds) do
    :erlang.float_to_binary(seconds / 3600, decimals: 2) <> "h"
  end

  defp local_timestamp(timestamp) do
    case unix(timestamp) do
      nil -> "-"
      value -> format_unix(value)
    end
  end

  defp unix(nil), do: nil

  defp unix(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} -> DateTime.to_unix(datetime, :second)
      {:error, _reason} -> nil
    end
  end

  defp pad(value, count), do: value |> Integer.to_string() |> String.pad_leading(count, "0")

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
          --root PATH  Use a specific histlog data root
          --json       Output JSON with full metadata
    """
  end
end
