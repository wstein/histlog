defmodule Histlog.Database.Schema do
  @moduledoc """
  SQLite schema for histlog's v1 materialized query database.
  """

  alias Histlog.Database

  @version 1

  def version, do: @version

  def ensure(conn) do
    with :ok <- Database.execute(conn, ddl()),
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

  def ddl do
    """
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS schema_metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS processed_sessions (
      session_file TEXT PRIMARY KEY,
      session_id TEXT,
      date TEXT NOT NULL,
      processed_at TEXT NOT NULL,
      schema_version INTEGER NOT NULL,
      events_count INTEGER NOT NULL,
      executions_count INTEGER NOT NULL,
      source_checksum TEXT NOT NULL
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
      duration_ms INTEGER,
      exit_status INTEGER,
      completeness TEXT,
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
