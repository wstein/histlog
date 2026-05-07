#!/usr/bin/env elixir

__ENV__.file
|> Path.dirname()
|> Path.join("../app/_build/{dev,test,prod}/lib/*/ebin")
|> Path.expand()
|> Path.wildcard()
|> Enum.each(&:code.add_patha(String.to_charlist(&1)))

defmodule Histlog.LegacyDbMigration do
  @moduledoc false

  @required_legacy_tables ~w(shells ttys paths sessions cmd_texts commands)

  def main(argv \\ System.argv()) do
    {opts, args, invalid} =
      OptionParser.parse(argv,
        strict: [output: :string, help: :boolean],
        aliases: [o: :output, h: :help]
      )

    cond do
      invalid != [] ->
        raise "invalid options: #{inspect(invalid)}"

      Keyword.get(opts, :help, false) ->
        IO.write(help())

      true ->
        [db_path | _] = args ++ [default_db_path()]
        migrate!(Path.expand(db_path), Keyword.get(opts, :output))
    end
  rescue
    exception ->
      IO.puts(:stderr, "legacy-db-migration: #{Exception.message(exception)}")
      System.halt(1)
  end

  defp migrate!(db_path, output_path) do
    root = repo_root()
    load_histlog_modules!(root)

    unless File.exists?(db_path) do
      raise "database does not exist: #{db_path}"
    end

    timestamp = timestamp()
    backup_path = db_path <> ".backup-" <> timestamp
    new_path = output_path |> new_db_path(db_path, timestamp) |> Path.expand()

    File.mkdir_p!(Path.dirname(backup_path))
    File.cp!(db_path, backup_path)
    File.rm(new_path)

    {:ok, conn} = Exqlite.Sqlite3.open(new_path)

    report =
      try do
        :ok = Histlog.Database.Schema.ensure(conn)
        :ok = Histlog.Database.exec(conn, "ATTACH DATABASE ? AS legacy", [backup_path])
        validate_legacy_schema!(conn)

        checksum = sha256!(backup_path)

        :ok =
          Histlog.Database.transaction(conn, fn ->
            with :ok <- insert_dimensions(conn),
                 :ok <- insert_import_batch(conn, backup_path),
                 :ok <- insert_command_texts(conn),
                 :ok <- insert_sessions(conn),
                 :ok <- insert_session_commands(conn),
                 :ok <- insert_orphan_import_commands(conn),
                 :ok <- insert_processed_sessions(conn, checksum) do
              :ok
            end
          end)

        migration_report(conn, db_path, backup_path, new_path)
      after
        Exqlite.Sqlite3.close(conn)
      end

    unless output_path do
      File.rename!(new_path, db_path)
    end

    IO.puts(JSON.encode!(report))
  end

  defp insert_dimensions(conn) do
    with :ok <-
           Histlog.Database.exec(conn, "INSERT OR IGNORE INTO hosts (name) VALUES ('legacy')"),
         :ok <-
           Histlog.Database.execute(conn, """
           INSERT OR IGNORE INTO shells (name, version)
           SELECT DISTINCT COALESCE(NULLIF(path, ''), 'unknown'), version
           FROM legacy.shells;
           """),
         :ok <-
           Histlog.Database.execute(conn, """
           INSERT OR IGNORE INTO ttys (device)
           SELECT DISTINCT device
           FROM legacy.ttys
           WHERE device IS NOT NULL AND device != '';
           """) do
      Histlog.Database.execute(conn, """
      INSERT OR IGNORE INTO paths (path, type)
      SELECT DISTINCT path,
        CASE WHEN type IN ('f', 'd') THEN type ELSE 'u' END
      FROM legacy.paths
      WHERE path IS NOT NULL AND path != '';
      """)
    end
  end

  defp insert_import_batch(conn, backup_path) do
    records = count_value!(conn, "SELECT COUNT(*) FROM legacy.commands WHERE session_id IS NULL")

    Histlog.Database.exec(
      conn,
      """
      INSERT INTO imports (
        import_batch_id, source, source_path, imported_at, records_count, warnings_count, report_json
      )
      VALUES ('legacy-histlog-db-orphans', 'legacy_histlog_db', ?, ?, ?, 0, ?)
      """,
      [
        backup_path,
        now_iso(),
        records,
        JSON.encode!(%{
          "source" => "legacy_histlog_db",
          "note" => "Commands without a legacy session_id are represented as imported rows."
        })
      ]
    )
  end

  defp insert_command_texts(conn) do
    Histlog.Database.execute(conn, """
    INSERT OR IGNORE INTO cmd_texts (command)
    SELECT DISTINCT command
    FROM legacy.cmd_texts
    WHERE command IS NOT NULL AND command != '';
    """)
  end

  defp insert_sessions(conn) do
    Histlog.Database.execute(conn, """
    WITH session_bounds AS (
      SELECT
        session_id,
        MIN(start_time) AS first_start,
        MAX(COALESCE(start_time, 0) + COALESCE(duration, 0)) AS last_end
      FROM legacy.commands
      WHERE session_id IS NOT NULL
      GROUP BY session_id
    )
    INSERT INTO sessions (
      session_uid, session_file, date, host_id, shell_id, tty_id, cwd_id,
      pid, parent_pid, started_at, ended_at
    )
    SELECT
      'legacy:' || s.id,
      'legacy-histlog.db-session-' || s.id,
      date(datetime(COALESCE(s.start_time, b.first_start, strftime('%s', 'now')), 'unixepoch')),
      (SELECT id FROM hosts WHERE name = 'legacy'),
      (SELECT id FROM shells WHERE name = COALESCE(NULLIF(sh.path, ''), 'unknown')),
      (SELECT id FROM ttys WHERE device = t.device),
      (SELECT id FROM paths WHERE path = p.path),
      s.pid,
      s.parent_pid,
      CASE
        WHEN COALESCE(s.start_time, b.first_start) IS NULL THEN NULL
        ELSE strftime('%Y-%m-%dT%H:%M:%fZ', COALESCE(s.start_time, b.first_start), 'unixepoch')
      END,
      CASE
        WHEN b.last_end IS NULL OR b.last_end = 0 THEN NULL
        ELSE strftime('%Y-%m-%dT%H:%M:%fZ', b.last_end, 'unixepoch')
      END
    FROM legacy.sessions s
    LEFT JOIN legacy.shells sh ON s.shell_id = sh.id
    LEFT JOIN legacy.ttys t ON s.tty_id = t.id
    LEFT JOIN legacy.paths p ON s.path_id = p.id
    LEFT JOIN session_bounds b ON b.session_id = s.id;
    """)
  end

  defp insert_session_commands(conn) do
    Histlog.Database.execute(conn, """
    INSERT INTO commands (
      session_id, exec_id, import_batch_id, import_row_index, date,
      cmd_text_id, cwd_id, timestamp, duration_ms, exit_status,
      completeness, source, is_private, is_assisted
    )
    SELECT
      ns.id,
      c.id,
      NULL,
      NULL,
      date(datetime(COALESCE(c.start_time, strftime('%s', 'now')), 'unixepoch')),
      nct.id,
      np.id,
      CASE
        WHEN c.start_time IS NULL THEN NULL
        ELSE strftime('%Y-%m-%dT%H:%M:%fZ', c.start_time, 'unixepoch')
      END,
      CASE
        WHEN c.duration IS NULL THEN NULL
        ELSE CAST(ROUND(c.duration * 1000) AS INTEGER)
      END,
      c.exit_code,
      CASE
        WHEN c.start_time IS NOT NULL AND c.duration IS NOT NULL AND c.exit_code IS NOT NULL
          THEN 'complete'
        ELSE 'partial'
      END,
      'session',
      COALESCE(c.is_private, 0),
      COALESCE(c.is_assisted, 0)
    FROM legacy.commands c
    JOIN legacy.sessions os ON c.session_id = os.id
    JOIN sessions ns ON ns.session_uid = 'legacy:' || os.id
    JOIN legacy.cmd_texts oct ON c.cmd_text_id = oct.id
    JOIN cmd_texts nct ON nct.command = oct.command
    LEFT JOIN legacy.paths op ON COALESCE(c.path_new_id, c.path_old_id) = op.id
    LEFT JOIN paths np ON np.path = op.path
    WHERE oct.command IS NOT NULL AND oct.command != '';
    """)
  end

  defp insert_orphan_import_commands(conn) do
    Histlog.Database.execute(conn, """
    INSERT INTO commands (
      session_id, exec_id, import_batch_id, import_row_index, date,
      cmd_text_id, cwd_id, timestamp, duration_ms, exit_status,
      completeness, source, is_private, is_assisted, import_shell_id
    )
    SELECT
      NULL,
      NULL,
      'legacy-histlog-db-orphans',
      c.id,
      date(datetime(COALESCE(c.start_time, strftime('%s', 'now')), 'unixepoch')),
      nct.id,
      np.id,
      CASE
        WHEN c.start_time IS NULL THEN NULL
        ELSE strftime('%Y-%m-%dT%H:%M:%fZ', c.start_time, 'unixepoch')
      END,
      CASE
        WHEN c.duration IS NULL THEN NULL
        ELSE CAST(ROUND(c.duration * 1000) AS INTEGER)
      END,
      c.exit_code,
      'partial',
      'import',
      COALESCE(c.is_private, 0),
      COALESCE(c.is_assisted, 0),
      NULL
    FROM legacy.commands c
    JOIN legacy.cmd_texts oct ON c.cmd_text_id = oct.id
    JOIN cmd_texts nct ON nct.command = oct.command
    LEFT JOIN legacy.paths op ON COALESCE(c.path_new_id, c.path_old_id) = op.id
    LEFT JOIN paths np ON np.path = op.path
    WHERE c.session_id IS NULL
      AND oct.command IS NOT NULL
      AND oct.command != '';
    """)
  end

  defp insert_processed_sessions(conn, checksum) do
    Histlog.Database.exec(
      conn,
      """
      INSERT INTO processed_sessions (
        date, session_file, session_uid, processed_at, schema_version,
        events_count, commands_count, source_checksum
      )
      SELECT
        s.date,
        s.session_file,
        s.session_uid,
        ?,
        ?,
        COUNT(c.id),
        COUNT(c.id),
        ?
      FROM sessions s
      LEFT JOIN commands c ON c.session_id = s.id AND c.source = 'session'
      WHERE s.session_uid LIKE 'legacy:%'
      GROUP BY s.date, s.session_file, s.session_uid
      """,
      [now_iso(), Histlog.Database.Schema.version(), checksum]
    )
  end

  defp migration_report(conn, original_path, backup_path, new_path) do
    %{
      "original_db" => original_path,
      "backup_db" => backup_path,
      "new_db" => new_path,
      "schema_version" => Histlog.Database.Schema.version(),
      "legacy_commands" => scalar_value!(conn, "SELECT COUNT(*) AS value FROM legacy.commands"),
      "migrated_commands" => scalar_value!(conn, "SELECT COUNT(*) AS value FROM commands"),
      "migrated_sessions" => scalar_value!(conn, "SELECT COUNT(*) AS value FROM sessions"),
      "orphan_imported_commands" =>
        scalar_value!(
          conn,
          """
          SELECT COUNT(*) AS value
          FROM commands
          WHERE import_batch_id = 'legacy-histlog-db-orphans'
          """
        ),
      "skipped_empty_commands" =>
        scalar_value!(
          conn,
          """
          SELECT COUNT(*) AS value
          FROM legacy.commands c
          LEFT JOIN legacy.cmd_texts ct ON c.cmd_text_id = ct.id
          WHERE ct.command IS NULL OR ct.command = ''
          """
        )
    }
  end

  defp validate_legacy_schema!(conn) do
    existing =
      conn
      |> query_maps!("""
      SELECT name
      FROM legacy.sqlite_master
      WHERE type = 'table'
      """)
      |> Enum.map(& &1.name)
      |> MapSet.new()

    missing = Enum.reject(@required_legacy_tables, &MapSet.member?(existing, &1))

    if missing != [] do
      raise "legacy database is missing required tables: #{Enum.join(missing, ", ")}"
    end
  end

  defp scalar_value!(conn, sql) do
    case Histlog.Database.query_value(conn, sql) do
      {:ok, value} -> value
      {:error, reason} -> raise "scalar query failed: #{inspect(reason)}"
    end
  end

  defp count_value!(conn, sql) do
    case Histlog.Database.query_value(conn, "SELECT COUNT(*) AS value FROM (#{sql})") do
      {:ok, count} -> count
      {:error, reason} -> raise "count query failed: #{inspect(reason)}"
    end
  end

  defp query_maps!(conn, sql) do
    case Histlog.Database.query_maps(conn, sql) do
      {:ok, rows} -> rows
      {:error, reason} -> raise "query failed: #{inspect(reason)}"
    end
  end

  defp new_db_path(nil, db_path, timestamp), do: db_path <> ".new-" <> timestamp
  defp new_db_path(output_path, _db_path, _timestamp), do: output_path

  defp default_db_path do
    Path.join([System.user_home!(), ".local", "share", "histlog", "histlog.db"])
  end

  defp repo_root do
    __ENV__.file
    |> Path.dirname()
    |> Path.join("..")
    |> Path.expand()
  end

  defp load_histlog_modules!(root) do
    root
    |> Path.join("app/_build/{dev,test,prod}/lib/*/ebin")
    |> Path.wildcard()
    |> Enum.each(&:code.add_patha(String.to_charlist(&1)))

    unless Code.ensure_loaded?(Histlog.Database.Schema) do
      raise "Histlog modules are not built. Run `make build` or `make ci` first."
    end

    case Application.ensure_all_started(:exqlite) do
      {:ok, _apps} -> :ok
      {:error, reason} -> raise "failed to start exqlite: #{inspect(reason)}"
    end
  end

  defp timestamp do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%d%H%M%S")
  end

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp sha256!(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp help do
    """
    Usage:
      elixir scripts/migrate-legacy-histlog-db.exs [PATH] [--output PATH]

    Migrates a legacy histlog SQLite database into the current histlog.db projection schema.
    This is a standalone maintenance script, not a histlog CLI command.

    Default PATH:
      ~/.local/share/histlog/histlog.db

    Behavior without --output:
      1. copy PATH to PATH.backup-YYYYMMDDHHMMSS
      2. create PATH.new-YYYYMMDDHHMMSS
      3. import legacy rows into the new schema
      4. replace PATH with the new database

    Behavior with --output:
      1. copy PATH to PATH.backup-YYYYMMDDHHMMSS
      2. create the output database
      3. leave the original PATH in place
    """
  end
end

Histlog.LegacyDbMigration.main()
