defmodule Histlog.Database.Schema do
  @moduledoc """
  SQLite schema for histlog's v1 materialized query database.
  """

  alias Histlog.Database

  @version 2

  def version, do: @version

  def ensure(conn) do
    with :ok <- reset_incompatible_schema(conn),
         :ok <- Database.execute(conn, ddl()),
         :ok <-
           Database.exec(
             conn,
             """
             INSERT INTO schema_metadata (key, value)
             VALUES ('schema_version', ?)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value
             """,
             [Integer.to_string(@version)]
           ) do
      :ok
    end
  end

  def schema_version(conn) do
    Database.query_value(conn, "SELECT value FROM schema_metadata WHERE key = 'schema_version'")
  end

  defp reset_incompatible_schema(conn) do
    cond do
      incompatible_processed_sessions?(conn) ->
        drop_materialization(conn)

      incompatible_executions?(conn) ->
        drop_materialization(conn)

      true ->
        :ok
    end
  end

  defp incompatible_processed_sessions?(conn) do
    case Database.query_maps(conn, "PRAGMA table_info(processed_sessions)") do
      {:ok, []} ->
        false

      {:ok, rows} ->
        primary_keys =
          rows
          |> Enum.filter(&(&1.pk in [1, 2]))
          |> Enum.sort_by(& &1.pk)
          |> Enum.map(& &1.name)

        primary_keys != ["date", "session_file"]

      {:error, _reason} ->
        true
    end
  end

  defp incompatible_executions?(conn) do
    case Database.query_value(
           conn,
           """
           SELECT sql AS value
           FROM sqlite_master
           WHERE type = 'table' AND name = 'executions'
           """
         ) do
      {:ok, nil} -> false
      {:ok, sql} -> not String.contains?(sql, "CHECK (completeness")
      {:error, _reason} -> true
    end
  end

  defp drop_materialization(conn) do
    Database.execute(conn, """
    DROP TABLE IF EXISTS executions;
    DROP TABLE IF EXISTS sessions;
    DROP TABLE IF EXISTS processed_sessions;
    DROP TABLE IF EXISTS schema_metadata;
    """)
  end

  def ddl do
    """
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS schema_metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS processed_sessions (
      date TEXT NOT NULL,
      session_file TEXT NOT NULL,
      session_id TEXT,
      processed_at TEXT NOT NULL,
      schema_version INTEGER NOT NULL CHECK (schema_version > 0),
      events_count INTEGER NOT NULL CHECK (events_count >= 0),
      executions_count INTEGER NOT NULL CHECK (executions_count >= 0),
      source_checksum TEXT NOT NULL,
      PRIMARY KEY (date, session_file)
    );

    CREATE TABLE IF NOT EXISTS sessions (
      session_id TEXT PRIMARY KEY,
      session_file TEXT NOT NULL,
      date TEXT NOT NULL,
      host TEXT,
      shell TEXT,
      tty TEXT,
      process_id INTEGER,
      parent_process_id INTEGER,
      started_at TEXT,
      ended_at TEXT
    );

    CREATE TABLE IF NOT EXISTS executions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT,
      exec_id INTEGER,
      date TEXT NOT NULL,
      command TEXT,
      cwd TEXT,
      timestamp TEXT,
      duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
      exit_status INTEGER,
      completeness TEXT CHECK (completeness IN ('complete', 'partial', 'unknown')),
      shell TEXT,
      host TEXT,
      tty TEXT,
      source TEXT NOT NULL DEFAULT 'sqlite',
      UNIQUE(session_id, exec_id)
    );

    CREATE INDEX IF NOT EXISTS idx_processed_sessions_date
      ON processed_sessions(date);

    CREATE INDEX IF NOT EXISTS idx_sessions_date
      ON sessions(date);

    CREATE INDEX IF NOT EXISTS idx_executions_date
      ON executions(date);

    CREATE INDEX IF NOT EXISTS idx_executions_timestamp
      ON executions(timestamp);

    CREATE INDEX IF NOT EXISTS idx_executions_command
      ON executions(command);

    CREATE INDEX IF NOT EXISTS idx_executions_cwd
      ON executions(cwd);

    CREATE INDEX IF NOT EXISTS idx_executions_exit_status
      ON executions(exit_status);
    """
  end
end
