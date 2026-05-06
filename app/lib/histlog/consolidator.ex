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
    rebuild? = Keyword.get(opts, :rebuild, false)

    with :ok <- recover_pending(root, date),
         {:ok, manifest} <- read_manifest(manifest_path, date, rebuild?),
         {:ok, result} <- consolidate_new_sessions(root, date, manifest, rebuild?),
         :ok <- commit_materialization(root, date, result) do
      {:ok, result.manifest}
    end
  end

  defp read_manifest(_manifest_path, date, true), do: {:ok, Manifest.empty(date)}
  defp read_manifest(manifest_path, date, false), do: Manifest.read(manifest_path, date)

  defp consolidate_new_sessions(root, date, manifest, rebuild?) do
    session_paths =
      root
      |> Storage.closed_dir(date)
      |> Path.join("*.ndjson")
      |> Path.wildcard()
      |> Enum.sort()
      |> maybe_reject_processed(manifest, rebuild?)

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

    existing_daily = read_existing(daily_path, rebuild?)
    existing_exec = read_existing(exec_path, rebuild?)
    daily_content = existing_daily <> encode_rows(canonical_events)
    exec_content = existing_exec <> encode_rows(execution_rows)

    updates = %{
      "sessions_processed" => Enum.map(valid, fn {path, _events} -> Path.basename(path) end),
      "records_written" => count_ndjson_records(daily_content),
      "exec_records_written" => count_ndjson_records(exec_content),
      "checksum" => Manifest.checksum(daily_content),
      "exec_checksum" => Manifest.checksum(exec_content),
      "rebuilt" => rebuild?,
      "quarantined_sessions" => quarantined
    }

    {:ok,
     %{
       daily_path: daily_path,
       daily_content: daily_content,
       exec_path: exec_path,
       exec_content: exec_content,
       manifest: Manifest.merge(manifest, updates)
     }}
  end

  defp commit_materialization(root, date, result) do
    transaction = build_transaction(root, date, result)

    with :ok <- write_stage(transaction["daily"]["tmp"], result.daily_content),
         :ok <- write_stage(transaction["exec"]["tmp"], result.exec_content),
         :ok <- write_pending(root, date, transaction),
         :ok <- commit_transaction(transaction),
         :ok <- Manifest.write(Storage.manifest_path(root, date), result.manifest) do
      File.rm(pending_path(root, date))
      :ok
    end
  end

  defp recover_pending(root, date) do
    path = pending_path(root, date)

    case File.read(path) do
      {:ok, content} ->
        with {:ok, transaction} <- JSON.decode(content),
             :ok <- commit_transaction(transaction),
             :ok <- Manifest.write(Storage.manifest_path(root, date), transaction["manifest"]) do
          File.rm(path)
          :ok
        end

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_transaction(root, date, result) do
    %{
      "schema_version" => 1,
      "transaction" => "consolidation",
      "date" => Date.to_iso8601(date),
      "manifest" => result.manifest,
      "daily" => %{
        "target" => result.daily_path,
        "tmp" => staged_path(result.daily_path),
        "checksum" => Manifest.checksum(result.daily_content)
      },
      "exec" => %{
        "target" => result.exec_path,
        "tmp" => staged_path(result.exec_path),
        "checksum" => Manifest.checksum(result.exec_content)
      },
      "manifest_path" => Storage.manifest_path(root, date)
    }
  end

  defp commit_transaction(transaction) do
    with :ok <- commit_file(transaction["daily"]),
         :ok <- commit_file(transaction["exec"]) do
      :ok
    end
  end

  defp commit_file(%{"target" => target, "tmp" => tmp, "checksum" => checksum}) do
    cond do
      file_checksum(target) == {:ok, checksum} ->
        File.rm(tmp)
        :ok

      File.exists?(tmp) ->
        File.mkdir_p!(Path.dirname(target))
        File.rename(tmp, target)

      true ->
        {:error, {:missing_staged_file, tmp}}
    end
  end

  defp write_stage(path, content) do
    File.mkdir_p!(Path.dirname(path))

    with :ok <- File.write(path, content, [:binary]),
         {:ok, :ok} <- File.open(path, [:read, :binary], &:file.sync/1) do
      :ok
    end
  end

  defp write_pending(root, date, transaction) do
    Storage.atomic_write(pending_path(root, date), JSON.encode!(transaction) <> "\n")
  end

  defp pending_path(root, date), do: Storage.manifest_path(root, date) <> ".pending"

  defp staged_path(target) do
    target <> ".stage-" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))
  end

  defp file_checksum(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, Manifest.checksum(content)}
      {:error, _reason} -> :error
    end
  end

  defp load_valid_session(path, root, date) do
    with {:ok, events} <- Storage.read_events(path),
         :ok <- Schema.validate_session(events) do
      {:ok, events}
    else
      {:error, reason} ->
        quarantine(path, root, date, inspect(reason))
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
    session = session_started(events)
    session_id = session["session_id"]

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
        "shell" => session["shell"],
        "host" => session["host"],
        "tty" => session["tty"]
      }
    end)
  end

  defp session_started([%{"event" => "session_started"} = event | _events]), do: event
  defp session_started(_events), do: %{}

  defp catalog(events, event_type, id_field, value_field) do
    events
    |> Enum.filter(&(&1["event"] == event_type))
    |> Map.new(fn event -> {event[id_field], event[value_field]} end)
  end

  defp encode_rows(rows), do: Enum.map_join(rows, "", &(JSON.encode!(&1) <> "\n"))

  defp maybe_reject_processed(session_paths, _manifest, true), do: session_paths

  defp maybe_reject_processed(session_paths, manifest, false) do
    Enum.reject(session_paths, &Manifest.processed?(manifest, &1))
  end

  defp read_existing(_path, true), do: ""

  defp read_existing(path, false) do
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
