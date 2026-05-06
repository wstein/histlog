defmodule Histlog.Query.Render do
  @moduledoc false

  alias Histlog.Query.Time

  def write(rows, "table") do
    rows
    |> table_lines()
    |> Enum.each(&IO.write(&1 <> "\n"))

    :ok
  end

  def write(rows, "json") do
    IO.puts(JSON.encode!(rows))
    :ok
  end

  def write(rows, "yaml") do
    IO.write(yaml_rows(rows))
    :ok
  end

  def write(rows, "plain") do
    Enum.each(rows, &IO.write(to_string(&1["command"]) <> "\n"))
    :ok
  end

  def write(rows, format) when format in ["bash", "zsh", "fish", "nu", "powershell"] do
    rows
    |> Enum.map(& &1["command"])
    |> Enum.each(&IO.write(shell_history_line(&1, format) <> "\n"))

    :ok
  end

  defp table_lines(rows) do
    labels = session_labels(rows)

    [
      "#{color("Sess", "38;5;141")} #{color("Timestamp", "38;5;14")}          #{color(" Duration", "33")} #{color("Exit", "38;5;84")} Command",
      "--------------------------------------------------"
      | Enum.map(rows, &table_row(&1, labels))
    ]
  end

  defp table_row(row, labels) do
    session = Map.get(labels, row["session_id"], "????") |> color("38;5;141")
    timestamp = row["timestamp"] |> format_timestamp() |> color("38;5;14")
    duration = row["duration_ms"] |> format_duration() |> color("33")
    exit = row["exit_status"] |> format_exit() |> color(exit_color(row["exit_status"]))
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
    |> Time.local_timestamp()
    |> String.replace("T", " ")
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

  defp exit_color(nil), do: "38;5;8"
  defp exit_color(0), do: "38;5;84"
  defp exit_color(_status), do: "38;5;203"

  defp color(text, code), do: "\e[#{code}m#{text}\e[0m"

  defp shell_history_line(command, format) when format in ["bash", "zsh", "fish"],
    do: command || ""

  defp shell_history_line(command, "nu"), do: command || ""
  defp shell_history_line(command, "powershell"), do: command || ""

  defp yaml_rows(rows) do
    Enum.map_join(rows, "", fn row ->
      "- command: #{yaml_scalar(row["command"])}\n" <>
        "  timestamp: #{yaml_scalar(row["timestamp"])}\n" <>
        "  cwd: #{yaml_scalar(row["cwd"])}\n" <>
        "  exit_status: #{yaml_scalar(row["exit_status"])}\n" <>
        "  duration_ms: #{yaml_scalar(row["duration_ms"])}\n" <>
        "  session_id: #{yaml_scalar(row["session_id"])}\n"
    end)
  end

  defp yaml_scalar(nil), do: "null"
  defp yaml_scalar(value) when is_integer(value), do: Integer.to_string(value)
  defp yaml_scalar(value), do: inspect(to_string(value))
end
