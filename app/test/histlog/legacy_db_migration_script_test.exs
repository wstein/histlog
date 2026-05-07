defmodule Histlog.LegacyDbMigrationScriptTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias Histlog.Database

  @repo_root Path.expand("../../..", __DIR__)

  test "standalone script backs up and migrates a legacy histlog2 database" do
    root = tmp_dir()
    db_path = Path.join(root, "histlog.db")

    create_legacy_db!(db_path)

    {output, status} =
      System.cmd("elixir", ["scripts/migrate-legacy-histlog-db.exs", db_path],
        cd: @repo_root,
        stderr_to_stdout: true
      )

    assert status == 0, output

    assert [_backup] = Path.wildcard(db_path <> ".backup-*")
    assert {:ok, report} = JSON.decode(output)
    assert report["legacy_commands"] == 2
    assert report["migrated_commands"] == 2
    assert report["migrated_sessions"] == 1
    assert report["orphan_imported_commands"] == 1

    assert {:ok, rows} =
             Database.with_connection(root, fn conn ->
               Database.query_maps(
                 conn,
                 """
                 SELECT session_id, command, cwd, duration_ms, exit_status, source, shell
                 FROM history_view
                 ORDER BY command
                 """
               )
             end)

    assert [
             %{
               command: "echo orphan",
               cwd: "/tmp",
               duration_ms: 250,
               exit_status: 1,
               session_id: nil,
               source: "import"
             },
             %{
               command: "git status",
               cwd: "/tmp/project",
               duration_ms: 1500,
               exit_status: 0,
               session_id: "legacy:1",
               shell: "/bin/zsh",
               source: "session"
             }
           ] = rows

    assert {:ok, 1} =
             Database.with_connection(root, fn conn ->
               Database.query_value(conn, "SELECT COUNT(*) AS value FROM processed_sessions")
             end)
  end

  defp create_legacy_db!(path) do
    {:ok, conn} = Sqlite3.open(path)

    try do
      ddl =
        @repo_root
        |> Path.join("app/test/fixtures/legacy/histlog2.sql")
        |> File.read!()
        |> String.replace("CREATE TABLE sqlite_sequence(name,seq);\n", "")

      :ok = Sqlite3.execute(conn, ddl)

      exec!(conn, "INSERT INTO shells (id, path, version) VALUES (1, '/bin/zsh', '5.9')")
      exec!(conn, "INSERT INTO ttys (id, device) VALUES (1, '/dev/ttys001')")
      exec!(conn, "INSERT INTO paths (id, path, type) VALUES (1, '/tmp', 'd')")
      exec!(conn, "INSERT INTO paths (id, path, type) VALUES (2, '/tmp/project', 'd')")

      exec!(
        conn,
        """
        INSERT INTO sessions (
          id, shell_id, tty_id, path_id, pid, parent_pid, start_time, timezone
        )
        VALUES (1, 1, 1, 2, 123, 100, 1710000000.0, 'UTC')
        """
      )

      exec!(conn, "INSERT INTO cmd_texts (id, command) VALUES (1, 'git status')")
      exec!(conn, "INSERT INTO cmd_texts (id, command) VALUES (2, 'echo orphan')")

      exec!(
        conn,
        """
        INSERT INTO commands (
          id, session_id, cmd_text_id, path_old_id, path_new_id, start_time,
          duration, exit_code, is_private, is_assisted
        )
        VALUES (10, 1, 1, 2, 2, 1710000001.0, 1.5, 0, 0, 0)
        """
      )

      exec!(
        conn,
        """
        INSERT INTO commands (
          id, session_id, cmd_text_id, path_old_id, path_new_id, start_time,
          duration, exit_code, is_private, is_assisted
        )
        VALUES (11, NULL, 2, 1, 1, 1710000002.0, 0.25, 1, 0, 0)
        """
      )
    after
      Sqlite3.close(conn)
    end
  end

  defp exec!(conn, sql) do
    assert :ok = Sqlite3.execute(conn, sql)
  end

  defp tmp_dir do
    path =
      Path.join(System.tmp_dir!(), "histlog-legacy-migration-test-#{System.unique_integer()}")

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
