defmodule Histlog.Consolidator do
  @moduledoc """
  Materialization from closed session NDJSON files into histlog.db.
  """

  alias Histlog.Checksum
  alias Histlog.Database
  alias Histlog.Database.Schema
  alias Histlog.NDJSON
  alias Histlog.Schema, as: EventSchema
  alias Histlog.Storage

  @doc """
  Consolidates closed sessions for a date into the SQLite query database.
  """
  def consolidate(opts \\ []) do
    root = Storage.root(opts)
    date = Keyword.get(opts, :date, Date.utc_today())
    rebuild? = Keyword.get(opts, :rebuild, false)

    Storage.ensure_layout(root, date)

    Database.with_connection(root, fn conn ->
      with :ok <- Schema.ensure(conn) do
        Database.transaction(conn, fn ->
          consolidate_in_transaction(conn, root, date, rebuild?)
        end)
      end
    end)
  end

  defp consolidate_in_transaction(conn, root, date, rebuild?) do
    with :ok <- maybe_clear_date(conn, date, rebuild?) do
      session_paths = session_paths(root, date)

      {valid, quarantined} =
        Enum.reduce(session_paths, {[], []}, fn path, {valid, quarantined} ->
          case load_session_for_processing(conn, path, root, date, rebuild?) do
            {:ok, session} ->
              {[session | valid], quarantined}

            {:skipped, _session_file} ->
              {valid, quarantined}

            {:quarantined, entry} ->
              {valid, [entry | quarantined]}
          end
        end)

      valid = Enum.reverse(valid)
      quarantined = Enum.reverse(quarantined)
      processed_at = DateTime.utc_now() |> DateTime.to_iso8601()

      with :ok <- insert_sessions(conn, date, valid, processed_at) do
        {:ok, report(conn, root, date, valid, quarantined, rebuild?)}
      end
    end
  end

  defp maybe_clear_date(_conn, _date, false), do: :ok

  defp maybe_clear_date(conn, date, true) do
    date = Date.to_iso8601(date)

    with :ok <- Database.exec(conn, "DELETE FROM executions WHERE date = ?", [date]),
         :ok <- Database.exec(conn, "DELETE FROM sessions WHERE date = ?", [date]),
         :ok <- Database.exec(conn, "DELETE FROM processed_sessions WHERE date = ?", [date]) do
      :ok
    end
  end

  defp session_paths(root, date) do
    root
    |> Storage.closed_dir(date)
    |> Path.join("*.ndjson")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp processed?(conn, date, path, checksum) do
    case Database.query_value(
           conn,
           """
           SELECT 1 AS value
           FROM processed_sessions
           WHERE date = ?
             AND session_file = ?
             AND source_checksum = ?
             AND schema_version = ?
           LIMIT 1
           """,
           [Date.to_iso8601(date), Path.basename(path), checksum, Schema.version()]
         ) do
      {:ok, 1} -> true
      _ -> false
    end
  end

  defp load_session_for_processing(conn, path, root, date, rebuild?) do
    with {:ok, content} <- File.read(path) do
      checksum = Checksum.sha256(content)

      if !rebuild? and processed?(conn, date, path, checksum) do
        {:skipped, Path.basename(path)}
      else
        load_valid_session(path, root, date, content, checksum)
      end
    else
      {:error, reason} ->
        quarantine(path, root, date, inspect(reason))
    end
  end

  defp load_valid_session(path, root, date, content, checksum) do
    with {:ok, events} <- NDJSON.decode(content),
         :ok <- EventSchema.validate_session(events) do
      {:ok,
       %{
         path: path,
         basename: Path.basename(path),
         events: events,
         source_checksum: checksum,
         execution_rows: derive_execution_rows(events)
       }}
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

  defp insert_sessions(conn, date, sessions, processed_at) do
    Enum.reduce_while(sessions, :ok, fn session, :ok ->
      case insert_session(conn, date, session, processed_at) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_session(conn, date, materialized, processed_at) do
    session = session_started(materialized.events)
    ended = session_ended(materialized.events)
    date_string = Date.to_iso8601(date)
    session_id = session["session_id"]

    with :ok <- delete_stale_session_materialization(conn, date_string, materialized.basename),
         :ok <-
           Database.exec(
             conn,
             """
             INSERT INTO sessions (
               session_id, session_file, date, host, shell, tty, process_id,
               parent_process_id, started_at, ended_at
             )
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(session_id) DO UPDATE SET
               session_file = excluded.session_file,
               date = excluded.date,
               host = excluded.host,
               shell = excluded.shell,
               tty = excluded.tty,
               process_id = excluded.process_id,
               parent_process_id = excluded.parent_process_id,
               started_at = excluded.started_at,
               ended_at = excluded.ended_at
             """,
             [
               session_id,
               materialized.basename,
               date_string,
               session["host"],
               session["shell"],
               session["tty"],
               session["process_id"],
               session["parent_process_id"],
               session["timestamp"],
               ended["timestamp"]
             ]
           ),
         :ok <- insert_execution_rows(conn, date, materialized.execution_rows),
         :ok <-
           Database.exec(
             conn,
             """
             INSERT INTO processed_sessions (
               date, session_file, session_id, processed_at, schema_version,
               events_count, executions_count, source_checksum
             )
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(date, session_file) DO UPDATE SET
               session_id = excluded.session_id,
               processed_at = excluded.processed_at,
               schema_version = excluded.schema_version,
               events_count = excluded.events_count,
               executions_count = excluded.executions_count,
               source_checksum = excluded.source_checksum
             """,
             [
               date_string,
               materialized.basename,
               session_id,
               processed_at,
               Schema.version(),
               length(materialized.events),
               length(materialized.execution_rows),
               materialized.source_checksum
             ]
           ) do
      :ok
    end
  end

  defp delete_stale_session_materialization(conn, date_string, session_file) do
    with {:ok, rows} <-
           Database.query_maps(
             conn,
             """
             SELECT session_id
             FROM processed_sessions
             WHERE date = ? AND session_file = ?
             """,
             [date_string, session_file]
           ),
         :ok <-
           Enum.reduce_while(rows, :ok, fn row, :ok ->
             case delete_session_rows(conn, row.session_id) do
               :ok -> {:cont, :ok}
               {:error, reason} -> {:halt, {:error, reason}}
             end
           end),
         :ok <-
           Database.exec(
             conn,
             "DELETE FROM processed_sessions WHERE date = ? AND session_file = ?",
             [date_string, session_file]
           ) do
      :ok
    end
  end

  defp delete_session_rows(_conn, nil), do: :ok

  defp delete_session_rows(conn, session_id) do
    with :ok <- Database.exec(conn, "DELETE FROM executions WHERE session_id = ?", [session_id]),
         :ok <- Database.exec(conn, "DELETE FROM sessions WHERE session_id = ?", [session_id]) do
      :ok
    end
  end

  defp insert_execution_rows(conn, date, rows) do
    Enum.reduce_while(rows, :ok, fn row, :ok ->
      case insert_execution_row(conn, date, row) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_execution_row(conn, date, row) do
    Database.exec(
      conn,
      """
      INSERT INTO executions (
        session_id, exec_id, date, command, cwd, timestamp, duration_ms,
        exit_status, completeness, shell, host, tty, source
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'sqlite')
      ON CONFLICT(session_id, exec_id) DO UPDATE SET
        date = excluded.date,
        command = excluded.command,
        cwd = excluded.cwd,
        timestamp = excluded.timestamp,
        duration_ms = excluded.duration_ms,
        exit_status = excluded.exit_status,
        completeness = excluded.completeness,
        shell = excluded.shell,
        host = excluded.host,
        tty = excluded.tty,
        source = excluded.source
      """,
      [
        row["session_id"],
        row["exec_id"],
        Date.to_iso8601(date),
        row["command"],
        row["cwd"],
        row["timestamp"],
        row["duration_ms"],
        row["exit_status"],
        row["completeness"],
        row["shell"],
        row["host"],
        row["tty"]
      ]
    )
  end

  defp report(conn, root, date, processed, quarantined, rebuild?) do
    date_string = Date.to_iso8601(date)

    {:ok, records_written} =
      count_value(
        conn,
        "SELECT COALESCE(SUM(events_count), 0) FROM processed_sessions WHERE date = ?",
        [date_string]
      )

    {:ok, exec_records_written} =
      count_value(conn, "SELECT COUNT(*) FROM executions WHERE date = ?", [date_string])

    %{
      "schema_version" => Schema.version(),
      "date" => date_string,
      "database_path" => Storage.database_path(root),
      "sessions_processed" => Enum.map(processed, & &1.basename),
      "records_written" => records_written,
      "exec_records_written" => exec_records_written,
      "rebuilt" => rebuild?,
      "quarantined_sessions" => quarantined
    }
  end

  defp count_value(conn, sql, params) do
    Database.query_value(conn, "SELECT (#{sql}) AS value", params)
  end

  def derive_execution_rows(events) do
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
        "tty" => session["tty"],
        "source" => "sqlite"
      }
    end)
  end

  defp session_started([%{"event" => "session_started"} = event | _events]), do: event
  defp session_started(_events), do: %{}

  defp session_ended(events) do
    Enum.find(events, %{}, &(&1["event"] == "session_ended"))
  end

  defp catalog(events, event_type, id_field, value_field) do
    events
    |> Enum.filter(&(&1["event"] == event_type))
    |> Map.new(fn event -> {event[id_field], event[value_field]} end)
  end
end
