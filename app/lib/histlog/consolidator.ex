defmodule Histlog.Consolidator do
  @moduledoc """
  Daily materialization from closed session NDJSON files.
  """

  alias Histlog.Manifest
  alias Histlog.Schema
  alias Histlog.Storage

  @doc """
  Consolidates closed sessions for a date.
  """
  def consolidate(opts \\ []) do
    root = Storage.root(opts)
    date = Keyword.get(opts, :date, Date.utc_today())

    Storage.ensure_layout(root, date)

    manifest_path = Storage.manifest_path(root, date)

    with {:ok, manifest} <- Manifest.read(manifest_path, date),
         {:ok, result} <- consolidate_new_sessions(root, date, manifest),
         :ok <- Manifest.write(manifest_path, result.manifest) do
      {:ok, result.manifest}
    end
  end

  defp consolidate_new_sessions(root, date, manifest) do
    session_paths =
      root
      |> Storage.closed_dir(date)
      |> Path.join("*.ndjson")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.reject(&Manifest.processed?(manifest, &1))

    {valid, quarantined} =
      Enum.reduce(session_paths, {[], []}, fn path, {valid, quarantined} ->
        case load_valid_session(path, root, date) do
          {:ok, events} ->
            {[{path, events} | valid], quarantined}

          {:quarantined, entry} ->
            {valid, [entry | quarantined]}
        end
      end)

    valid = Enum.reverse(valid)
    quarantined = Enum.reverse(quarantined)

    canonical_events = Enum.flat_map(valid, fn {_path, events} -> events end)
    execution_rows = Enum.flat_map(valid, fn {_path, events} -> derive_execution_rows(events) end)

    daily_path = Storage.daily_events_path(root, date)
    exec_path = Storage.daily_exec_path(root, date)

    existing_daily = read_existing(daily_path)
    existing_exec = read_existing(exec_path)
    daily_content = existing_daily <> encode_rows(canonical_events)
    exec_content = existing_exec <> encode_rows(execution_rows)

    with :ok <- Storage.atomic_write(daily_path, daily_content),
         :ok <- Storage.atomic_write(exec_path, exec_content) do
      updates = %{
        "sessions_processed" => Enum.map(valid, fn {path, _events} -> Path.basename(path) end),
        "records_written" => count_ndjson_records(daily_content),
        "exec_records_written" => count_ndjson_records(exec_content),
        "checksum" => Manifest.checksum(daily_content),
        "exec_checksum" => Manifest.checksum(exec_content),
        "quarantined_sessions" => quarantined
      }

      {:ok, %{manifest: Manifest.merge(manifest, updates)}}
    end
  end

  defp load_valid_session(path, root, date) do
    with {:ok, events} <- Storage.read_events(path),
         :ok <- Schema.validate_sequence(events),
         :ok <- validate_session_header(events) do
      {:ok, events}
    else
      {:error, reason} ->
        quarantine(path, root, date, inspect(reason))
    end
  end

  defp validate_session_header([]), do: {:error, :empty_session}

  defp validate_session_header([
         %{"event" => "session_started", "session_id" => session_id} | _events
       ])
       when is_binary(session_id) and session_id != "" do
    :ok
  end

  defp validate_session_header(_events), do: {:error, :missing_session_header}

  defp session_id(events) do
    case events do
      [%{"event" => "session_started", "session_id" => session_id} | _rest] -> session_id
      _other -> nil
    end
  end

  defp quarantine(path, root, date, reason) do
    destination =
      case Storage.quarantine_session(path, root, date) do
        {:ok, destination} -> destination
        {:error, move_reason} -> "quarantine_failed: #{inspect(move_reason)}"
      end

    {:quarantined,
     %{
       "session" => Path.basename(path),
       "reason" => reason,
       "quarantine_path" => destination
     }}
  end

  defp derive_execution_rows(events) do
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
        "completeness" => event["completeness"]
      }
    end)
  end

  defp catalog(events, event_type, id_field, value_field) do
    events
    |> Enum.filter(&(&1["event"] == event_type))
    |> Map.new(fn event -> {event[id_field], event[value_field]} end)
  end

  defp encode_rows(rows), do: Enum.map_join(rows, "", &(JSON.encode!(&1) <> "\n"))

  defp read_existing(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, :enoent} -> ""
    end
  end

  defp count_ndjson_records(""), do: 0

  defp count_ndjson_records(content) do
    content
    |> String.split("\n", trim: true)
    |> length()
  end
end
