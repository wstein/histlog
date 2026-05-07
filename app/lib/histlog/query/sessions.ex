defmodule Histlog.Query.Sessions do
  @moduledoc """
  Semantic session summaries derived from query execution rows.
  """

  def rows(execution_rows) do
    execution_rows
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
end
