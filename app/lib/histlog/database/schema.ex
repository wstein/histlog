defmodule Histlog.Database.Schema do
  @moduledoc """
  SQLite schema for histlog's v1 materialized query database.

  The schema is a relational projection inspired by histlog2's useful shape, but it
  is not compatible with histlog2 tables or migrations.
  """

  alias Histlog.Database

  @version 5
  @tables ~w(schema_metadata processed_sessions hosts shells ttys paths sessions imports cmd_texts commands)

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
    expected_version = Integer.to_string(@version)

    case schema_version(conn) do
      {:ok, nil} -> maybe_drop_legacy_projection(conn)
      {:ok, ^expected_version} -> :ok
      {:ok, _old_version} -> drop_materialization(conn)
      {:error, _reason} -> maybe_drop_legacy_projection(conn)
    end
  end

  defp maybe_drop_legacy_projection(conn) do
    if legacy_projection?(conn), do: drop_materialization(conn), else: :ok
  end

  defp legacy_projection?(conn) do
    case Database.query_value(
           conn,
           """
           SELECT COUNT(*) AS value
           FROM sqlite_master
           WHERE type = 'table'
             AND name IN ('executions', 'cmd_texts', 'commands', 'processed_sessions')
           """
         ) do
      {:ok, 0} -> false
      {:ok, _count} -> true
      {:error, _reason} -> true
    end
  end

  defp drop_materialization(conn) do
    Database.execute(conn, """
    DROP VIEW IF EXISTS history_view;
    DROP VIEW IF EXISTS sessions_view;
    DROP TABLE IF EXISTS commands;
    DROP TABLE IF EXISTS cmd_texts;
    DROP TABLE IF EXISTS imports;
    DROP TABLE IF EXISTS sessions;
    DROP TABLE IF EXISTS paths;
    DROP TABLE IF EXISTS ttys;
    DROP TABLE IF EXISTS shells;
    DROP TABLE IF EXISTS hosts;
    DROP TABLE IF EXISTS processed_sessions;
    DROP TABLE IF EXISTS schema_metadata;
    """)
  end

  def tables, do: @tables

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
      session_uid TEXT,
      processed_at TEXT NOT NULL,
      schema_version INTEGER NOT NULL CHECK (schema_version > 0),
      events_count INTEGER NOT NULL CHECK (events_count >= 0),
      commands_count INTEGER NOT NULL CHECK (commands_count >= 0),
      source_checksum TEXT NOT NULL,
      PRIMARY KEY (date, session_file)
    );

    CREATE TABLE IF NOT EXISTS hosts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS shells (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      version TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS ttys (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      device TEXT UNIQUE,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS paths (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      path TEXT UNIQUE NOT NULL,
      type TEXT NOT NULL DEFAULT 'u' CHECK (type IN ('f', 'd', 'u')),
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_uid TEXT UNIQUE NOT NULL,
      session_file TEXT NOT NULL,
      date TEXT NOT NULL,
      host_id INTEGER,
      shell_id INTEGER,
      tty_id INTEGER,
      cwd_id INTEGER,
      pid INTEGER,
      parent_pid INTEGER,
      started_at TEXT,
      ended_at TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (host_id) REFERENCES hosts(id),
      FOREIGN KEY (shell_id) REFERENCES shells(id),
      FOREIGN KEY (tty_id) REFERENCES ttys(id),
      FOREIGN KEY (cwd_id) REFERENCES paths(id)
    );

    CREATE TABLE IF NOT EXISTS imports (
      import_batch_id TEXT PRIMARY KEY,
      source TEXT NOT NULL,
      source_path TEXT,
      imported_at TEXT NOT NULL,
      records_count INTEGER NOT NULL CHECK (records_count >= 0),
      warnings_count INTEGER NOT NULL CHECK (warnings_count >= 0),
      report_json TEXT
    );

    CREATE TABLE IF NOT EXISTS cmd_texts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      command TEXT UNIQUE NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS commands (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER,
      exec_id INTEGER,
      import_batch_id TEXT,
      import_row_index INTEGER,
      date TEXT NOT NULL,
      cmd_text_id INTEGER NOT NULL,
      cwd_id INTEGER,
      timestamp TEXT,
      duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
      exit_status INTEGER,
      completeness TEXT CHECK (completeness IN ('complete', 'partial', 'unknown')),
      source TEXT NOT NULL CHECK (source IN ('session', 'import')),
      is_private INTEGER NOT NULL DEFAULT 0 CHECK (is_private IN (0, 1)),
      is_assisted INTEGER NOT NULL DEFAULT 0 CHECK (is_assisted IN (0, 1)),
      import_shell_id INTEGER,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (session_id) REFERENCES sessions(id),
      FOREIGN KEY (import_batch_id) REFERENCES imports(import_batch_id),
      FOREIGN KEY (cmd_text_id) REFERENCES cmd_texts(id),
      FOREIGN KEY (cwd_id) REFERENCES paths(id),
      FOREIGN KEY (import_shell_id) REFERENCES shells(id),
      UNIQUE(session_id, exec_id),
      UNIQUE(import_batch_id, import_row_index),
      CHECK (
        (
          source = 'session'
          AND session_id IS NOT NULL
          AND exec_id IS NOT NULL
          AND import_batch_id IS NULL
          AND import_row_index IS NULL
        )
        OR
        (
          source = 'import'
          AND session_id IS NULL
          AND exec_id IS NULL
          AND import_batch_id IS NOT NULL
          AND import_row_index IS NOT NULL
        )
      )
    );

    CREATE INDEX IF NOT EXISTS idx_processed_sessions_date
      ON processed_sessions(date);
    CREATE INDEX IF NOT EXISTS idx_hosts_name
      ON hosts(name);
    CREATE INDEX IF NOT EXISTS idx_shells_name
      ON shells(name);
    CREATE INDEX IF NOT EXISTS idx_ttys_device
      ON ttys(device);
    CREATE INDEX IF NOT EXISTS idx_paths_path
      ON paths(path);
    CREATE INDEX IF NOT EXISTS idx_paths_type
      ON paths(type);
    CREATE INDEX IF NOT EXISTS idx_sessions_date
      ON sessions(date);
    CREATE INDEX IF NOT EXISTS idx_sessions_shell_id
      ON sessions(shell_id);
    CREATE INDEX IF NOT EXISTS idx_sessions_cwd_id
      ON sessions(cwd_id);
    CREATE INDEX IF NOT EXISTS idx_cmd_texts_command
      ON cmd_texts(command);
    CREATE INDEX IF NOT EXISTS idx_commands_session_id
      ON commands(session_id);
    CREATE INDEX IF NOT EXISTS idx_commands_cmd_text_id
      ON commands(cmd_text_id);
    CREATE INDEX IF NOT EXISTS idx_commands_cwd_id
      ON commands(cwd_id);
    CREATE INDEX IF NOT EXISTS idx_commands_date
      ON commands(date);
    CREATE INDEX IF NOT EXISTS idx_commands_timestamp
      ON commands(timestamp);
    CREATE INDEX IF NOT EXISTS idx_commands_exit_status
      ON commands(exit_status);
    CREATE INDEX IF NOT EXISTS idx_commands_import_batch
      ON commands(import_batch_id);
    CREATE INDEX IF NOT EXISTS idx_commands_source
      ON commands(source);
    CREATE INDEX IF NOT EXISTS idx_commands_source_date
      ON commands(source, date);
    CREATE INDEX IF NOT EXISTS idx_commands_date_timestamp
      ON commands(date, timestamp);
    CREATE INDEX IF NOT EXISTS idx_commands_import_source
      ON commands(source, import_batch_id);
    CREATE INDEX IF NOT EXISTS idx_sessions_date_started_at
      ON sessions(date, started_at);

    CREATE VIEW IF NOT EXISTS history_view AS
      SELECT
        commands.id AS command_id,
        sessions.session_uid AS session_id,
        commands.exec_id AS exec_id,
        commands.import_batch_id AS import_batch_id,
        commands.import_row_index AS import_row_index,
        commands.date AS date,
        cmd_texts.command AS command,
        paths.path AS cwd,
        commands.timestamp AS timestamp,
        commands.duration_ms AS duration_ms,
        commands.exit_status AS exit_status,
        commands.completeness AS completeness,
        COALESCE(shells.name, import_shells.name) AS shell,
        hosts.name AS host,
        ttys.device AS tty,
        commands.source AS source,
        commands.is_private AS is_private,
        commands.is_assisted AS is_assisted
      FROM commands
      JOIN cmd_texts ON commands.cmd_text_id = cmd_texts.id
      LEFT JOIN paths ON commands.cwd_id = paths.id
      LEFT JOIN sessions ON commands.session_id = sessions.id
      LEFT JOIN shells ON sessions.shell_id = shells.id
      LEFT JOIN shells import_shells ON commands.import_shell_id = import_shells.id
      LEFT JOIN hosts ON sessions.host_id = hosts.id
      LEFT JOIN ttys ON sessions.tty_id = ttys.id;

    CREATE VIEW IF NOT EXISTS sessions_view AS
      SELECT
        sessions.id AS id,
        sessions.session_uid AS session_id,
        sessions.session_file AS session_file,
        sessions.date AS date,
        sessions.pid AS pid,
        sessions.parent_pid AS parent_pid,
        sessions.started_at AS started_at,
        sessions.ended_at AS ended_at,
        shells.name AS shell,
        hosts.name AS host,
        ttys.device AS tty,
        paths.path AS cwd
      FROM sessions
      LEFT JOIN shells ON sessions.shell_id = shells.id
      LEFT JOIN hosts ON sessions.host_id = hosts.id
      LEFT JOIN ttys ON sessions.tty_id = ttys.id
      LEFT JOIN paths ON sessions.cwd_id = paths.id;
    """
  end
end
