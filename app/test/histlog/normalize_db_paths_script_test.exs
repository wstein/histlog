defmodule Histlog.NormalizeDbPathsScriptTest do
  use ExUnit.Case, async: false

  alias Histlog.Database
  alias Histlog.Database.Schema

  @repo_root Path.expand("../../..", __DIR__)

  test "standalone script normalizes existing home paths and merges duplicates" do
    root = tmp_dir()
    home = System.user_home!()

    Database.with_connection(root, fn conn ->
      :ok = Schema.ensure(conn)

      :ok =
        Database.exec(conn, """
        INSERT INTO paths (id, path, type)
        VALUES
          (1, '#{home}/project', 'd'),
          (2, '~/project', 'u'),
          (3, '#{home}/project/file.txt', 'f')
        """)

      :ok =
        Database.exec(conn, """
        INSERT INTO cmd_texts (id, command) VALUES (1, 'cat ./file.txt')
        """)

      :ok =
        Database.exec(conn, """
        INSERT INTO sessions (
          id, session_uid, session_file, date, cwd_id, started_at
        )
        VALUES (1, 'session-1', 'session-1.ndjson', '2026-05-08', 1, '2026-05-08T10:00:00Z')
        """)

      :ok =
        Database.exec(conn, """
        INSERT INTO commands (
          id, session_id, exec_id, date, cmd_text_id, cwd_id, timestamp,
          completeness, source
        )
        VALUES (1, 1, 1, '2026-05-08', 1, 1, '2026-05-08T10:00:00Z', 'complete', 'session')
        """)

      :ok =
        Database.exec(conn, """
        INSERT INTO command_paths (
          command_id, path_id, arg_position, original_arg, resolved_path, path_exists
        )
        VALUES (1, 3, 0, './file.txt', '#{home}/project/file.txt', 1)
        """)
    end)

    {output, status} =
      System.cmd("elixir", ["scripts/normalize-db-paths.exs", "--root", root],
        cd: @repo_root,
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert {:ok, report} = JSON.decode(output)
    assert report["path_rows_changed"] == 2
    assert report["path_reference_updates"] == 1
    assert report["resolved_path_rows_changed"] == 1
    assert [_backup] = Path.wildcard(Path.join(root, "histlog.db.paths-backup-*"))

    assert {:ok, rows} =
             Database.with_connection(root, fn conn ->
               Database.query_maps(
                 conn,
                 """
                 SELECT paths.path, paths.type
                 FROM paths
                 ORDER BY paths.path
                 """
               )
             end)

    assert rows == [
             %{path: "~/project", type: "d"},
             %{path: "~/project/file.txt", type: "f"}
           ]

    assert {:ok, [%{cwd: "~/project"}]} =
             Database.with_connection(root, fn conn ->
               Database.query_maps(conn, "SELECT cwd FROM history_view")
             end)

    assert {:ok, [%{resolved_path: "~/project/file.txt"}]} =
             Database.with_connection(root, fn conn ->
               Database.query_maps(conn, "SELECT resolved_path FROM command_paths")
             end)
  end

  defp tmp_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "histlog-normalize-db-paths-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
