defmodule Histlog.Query do
  @moduledoc """
  Streaming file-based query helpers for derived execution rows.
  """

  alias Histlog.Storage

  @doc """
  Returns derived execution rows for a date matching simple filters.
  """
  def executions(opts \\ []) do
    root = Storage.root(opts)
    date = Keyword.get(opts, :date, Date.utc_today())
    filters = Keyword.get(opts, :filters, %{})

    rows =
      root
      |> daily_execution_rows(date)
      |> Kernel.++(live_execution_rows(root, date))
      |> Enum.filter(&matches?(&1, filters))

    {:ok, rows}
  end

  @doc """
  Returns canonical daily and live event rows for tail-like views.
  """
  def events(opts \\ []) do
    root = Storage.root(opts)
    date = Keyword.get(opts, :date, Date.utc_today())

    {:ok, daily_event_rows(root, date) ++ live_event_rows(root, date)}
  end

  defp daily_execution_rows(root, date) do
    path = Storage.daily_exec_path(root, date)

    if File.exists?(path) do
      read_ndjson_file(path)
    else
      []
    end
  end

  defp daily_event_rows(root, date) do
    path = Storage.daily_events_path(root, date)

    if File.exists?(path) do
      read_ndjson_file(path)
    else
      []
    end
  end

  defp live_event_rows(root, date) do
    root
    |> live_session_paths(date)
    |> Enum.flat_map(&read_ndjson_file/1)
  end

  defp live_execution_rows(root, date) do
    root
    |> live_session_paths(date)
    |> Enum.flat_map(&session_execution_rows/1)
  end

  defp live_session_paths(root, date) do
    root
    |> Storage.live_dir(date)
    |> Path.join("*.ndjson")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp session_execution_rows(path) do
    events = read_ndjson_file(path)
    commands = catalog(events, "command_defined", "command_id", "command")
    folders = catalog(events, "folder_defined", "folder_id", "folder")
    session_id = session_id(events)

    events
    |> Enum.filter(&(&1["event"] == "execution_observed"))
    |> Enum.map(fn event ->
      %{
        "event" => "execution",
        "session_id" => session_id,
        "exec_id" => event["exec_id"],
        "command" => Map.get(commands, event["command_id"]),
        "cwd" => Map.get(folders, event["cwd_id"]),
        "timestamp" => event["timestamp"],
        "duration_ms" => event["duration_ms"],
        "exit_status" => event["exit_status"],
        "completeness" => event["completeness"],
        "source" => "live"
      }
    end)
  end

  defp read_ndjson_file(path) do
    path
    |> File.stream!(:line, [])
    |> Stream.map(&JSON.decode!/1)
    |> Enum.to_list()
  end

  defp catalog(events, event_type, id_field, value_field) do
    events
    |> Enum.filter(&(&1["event"] == event_type))
    |> Map.new(fn event -> {event[id_field], event[value_field]} end)
  end

  defp session_id([%{"event" => "session_started", "session_id" => session_id} | _events]),
    do: session_id

  defp session_id(_events), do: nil

  defp matches?(row, filters) do
    Enum.all?(filters, fn
      {:command, command} -> String.contains?(row["command"] || "", command)
      {:cwd, cwd} -> row["cwd"] == cwd
      {:exit_status, status} -> row["exit_status"] == status
      {field, value} -> row[to_string(field)] == value
    end)
  end
end
