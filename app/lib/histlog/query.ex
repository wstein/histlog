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
    date = Keyword.get(opts, :date)
    filters = Keyword.get(opts, :filters, %{})

    rows =
      root
      |> execution_rows(date)
      |> Enum.filter(&matches?(&1, filters))

    {:ok, rows}
  end

  defp execution_rows(root, nil) do
    root
    |> available_dates()
    |> Enum.flat_map(&execution_rows(root, &1))
  end

  defp execution_rows(root, date) do
    root
    |> daily_execution_rows(date)
    |> Kernel.++(live_execution_rows(root, date))
    |> Kernel.++(imported_execution_rows(root, date))
  end

  defp daily_execution_rows(root, date) do
    path = Storage.daily_exec_path(root, date)

    if File.exists?(path) do
      read_ndjson_file(path)
    else
      []
    end
  end

  defp imported_execution_rows(root, date) do
    root
    |> Storage.imports_dir()
    |> Path.join("#{Date.to_iso8601(date)}-*.ndjson")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      path
      |> read_ndjson_file()
      |> Enum.filter(&(&1["event"] == "imported_execution"))
      |> Enum.map(&imported_execution_row/1)
    end)
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
    session = session_started(events)

    events
    |> Enum.filter(&(&1["event"] == "execution_observed"))
    |> Enum.map(fn event ->
      %{
        "event" => "execution",
        "session_id" => session["session_id"],
        "exec_id" => event["exec_id"],
        "command" => Map.get(commands, event["command_id"]),
        "cwd" => Map.get(folders, event["cwd_id"]),
        "timestamp" => event["timestamp"],
        "duration_ms" => event["duration_ms"],
        "exit_status" => event["exit_status"],
        "completeness" => event["completeness"],
        "shell" => session["shell"],
        "host" => session["host"],
        "tty" => session["tty"],
        "source" => "live"
      }
    end)
  end

  defp imported_execution_row(event) do
    %{
      "event" => "execution",
      "session_id" => nil,
      "command" => event["command"],
      "cwd" => event["cwd"],
      "timestamp" => event["timestamp"],
      "duration_ms" => event["duration_ms"],
      "exit_status" => event["exit_status"],
      "completeness" => "imported",
      "source" => "imported"
    }
  end

  defp available_dates(root) do
    root
    |> date_strings()
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn date ->
      case Date.from_iso8601(date) do
        {:ok, parsed} -> [parsed]
        {:error, _reason} -> []
      end
    end)
  end

  defp date_strings(root) do
    daily =
      root
      |> Storage.daily_dir()
      |> Path.join("*.exec.ndjson")
      |> Path.wildcard()
      |> Enum.map(fn path -> path |> Path.basename(".exec.ndjson") end)

    live =
      Path.join([root, "sessions", "live", "*"])
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)

    imports =
      root
      |> Storage.imports_dir()
      |> Path.join("*.ndjson")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        case Regex.run(~r/^(\d{4}-\d{2}-\d{2})-/, Path.basename(path)) do
          [_, date] -> [date]
          _ -> []
        end
      end)

    daily ++ live ++ imports
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

  defp session_started([%{"event" => "session_started"} = event | _events]), do: event
  defp session_started(_events), do: %{}

  defp matches?(row, filters) do
    Enum.all?(filters, fn
      {:command, command} -> String.contains?(row["command"] || "", command)
      {:cwd, cwd} -> row["cwd"] == cwd
      {:exit_status, status} -> row["exit_status"] == status
      {field, value} -> row[to_string(field)] == value
    end)
  end
end
