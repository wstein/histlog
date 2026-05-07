defmodule Histlog.DatabaseSchemaTest do
  use ExUnit.Case, async: true

  alias Histlog.Database
  alias Histlog.Database.Projection
  alias Histlog.Database.Schema

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "histlog-database-schema-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "creates the v1 materialization schema", %{root: root} do
    assert :ok =
             Database.with_connection(root, fn conn ->
               :ok = Schema.ensure(conn)

               assert {:ok, "6"} = Schema.schema_version(conn)

               assert {:ok, tables} =
                        Database.query_maps(
                          conn,
                          """
                          SELECT name
                          FROM sqlite_master
                          WHERE type = 'table'
                          ORDER BY name
                          """
                        )

               table_names = Enum.map(tables, & &1.name)

               for table <-
                     ~w(cmd_texts command_paths commands hosts imports paths processed_sessions schema_metadata sessions shells ttys) do
                 assert table in table_names
               end

               assert {:ok, processed_columns} =
                        Database.query_maps(conn, "PRAGMA table_info(processed_sessions)")

               primary_keys =
                 processed_columns
                 |> Enum.filter(&(&1.pk in [1, 2]))
                 |> Enum.sort_by(& &1.pk)
                 |> Enum.map(& &1.name)

               assert primary_keys == ["date", "session_file"]

               assert {:ok, command_columns} =
                        Database.query_maps(conn, "PRAGMA table_info(commands)")

               command_column_names = Enum.map(command_columns, & &1.name)
               assert "import_batch_id" in command_column_names
               assert "import_row_index" in command_column_names
               assert "cmd_text_id" in command_column_names

               assert {:ok, history_columns} =
                        Database.query_maps(conn, "PRAGMA table_info(history_view)")

               history_column_names = Enum.map(history_columns, & &1.name)
               assert "date" in history_column_names
               assert "command" in history_column_names
               assert "cwd" in history_column_names

               assert {:ok, indexes} =
                        Database.query_maps(
                          conn,
                          """
                          SELECT name
                          FROM sqlite_master
                          WHERE type = 'index'
                          ORDER BY name
                          """
                        )

               index_names = Enum.map(indexes, & &1.name)
               assert "idx_commands_date_timestamp" in index_names
               assert "idx_commands_source_date" in index_names
               assert "idx_commands_import_source" in index_names
               assert "idx_command_paths_command_id" in index_names
               assert "idx_command_paths_path_id" in index_names
               assert "idx_sessions_date_started_at" in index_names

               assert {:ok, cmd_text_id} = Projection.upsert_command_text(conn, "bad row")

               assert {:error, _reason} =
                        Database.exec(
                          conn,
                          """
                          INSERT INTO commands (
                            date, cmd_text_id, timestamp, completeness, source
                          )
                          VALUES ('2026-05-06', ?, '2026-05-06T20:00:00Z', 'complete', 'live')
                          """,
                          [cmd_text_id]
                        )

               assert {:error, _reason} =
                        Database.exec(
                          conn,
                          """
                          INSERT INTO commands (
                            date, cmd_text_id, timestamp, completeness, source
                          )
                          VALUES ('2026-05-06', ?, '2026-05-06T20:00:00Z', 'complete', 'session')
                          """,
                          [cmd_text_id]
                        )

               assert {:error, _reason} =
                        Database.exec(
                          conn,
                          """
                          INSERT INTO commands (
                            date, cmd_text_id, timestamp, completeness, source
                          )
                          VALUES ('2026-05-06', ?, '2026-05-06T20:00:00Z', 'partial', 'import')
                          """,
                          [cmd_text_id]
                        )

               :ok
             end)
  end

  test "reports incompatible projection resets", %{root: root} do
    assert :ok =
             Database.with_connection(root, fn conn ->
               assert {:ok, %{"schema_reset" => false}} = Schema.ensure_with_report(conn)

               :ok =
                 Database.exec(
                   conn,
                   "UPDATE schema_metadata SET value = 'old' WHERE key = 'schema_version'"
                 )

               assert {:ok, %{"schema_reset" => true}} = Schema.ensure_with_report(conn)
               assert {:ok, "6"} = Schema.schema_version(conn)

               :ok
             end)
  end

  test "upgrades unknown path type and rejects unexpected projection targets", %{root: root} do
    path = Path.join(root, "project")

    assert :ok =
             Database.with_connection(root, fn conn ->
               :ok = Schema.ensure(conn)

               assert {:ok, _path_id} = Projection.upsert_path(conn, path)

               assert {:ok, "u"} =
                        Database.query_value(
                          conn,
                          "SELECT type AS value FROM paths WHERE path = ?",
                          [
                            path
                          ]
                        )

               File.mkdir_p!(path)

               assert {:ok, _path_id} = Projection.upsert_path(conn, path)

               assert {:ok, "d"} =
                        Database.query_value(
                          conn,
                          "SELECT type AS value FROM paths WHERE path = ?",
                          [
                            path
                          ]
                        )

               assert {:error, {:invalid_projection_target, "commands", "source"}} =
                        Projection.upsert_named(conn, "commands", "source", "session")

               assert {:error, :missing_command} = Projection.upsert_command_text(conn, nil)
               assert {:error, :missing_command} = Projection.upsert_command_text(conn, "")

               :ok
             end)
  end

  test "projection updates duplicate session and import identities", %{root: root} do
    assert :ok =
             Database.with_connection(root, fn conn ->
               :ok = Schema.ensure(conn)

               materialized = %{
                 basename: "session-machine-1-1.ndjson",
                 first_cwd: "/repo",
                 session: %{
                   "session_id" => "session-1",
                   "host" => "machine",
                   "shell" => "zsh",
                   "tty" => "/dev/pts/1",
                   "process_id" => 1,
                   "parent_process_id" => 0,
                   "timestamp" => "2026-05-06T20:00:00Z"
                 },
                 ended: %{"timestamp" => "2026-05-06T20:00:10Z"}
               }

               assert {:ok, session_id} =
                        Projection.insert_session(conn, materialized, "2026-05-06")

               assert :ok =
                        Projection.insert_session_command(conn, session_id, "2026-05-06", %{
                          "exec_id" => 1,
                          "command" => "cat ./mix.exs missing",
                          "cwd" => "/repo",
                          "timestamp" => "2026-05-06T20:00:01Z",
                          "duration_ms" => 10,
                          "exit_status" => 0,
                          "completeness" => "complete"
                        })

               assert :ok =
                        Projection.insert_session_command(conn, session_id, "2026-05-06", %{
                          "exec_id" => 1,
                          "command" => "cat ./mix.exs #{Path.join(root, "other.txt")}",
                          "cwd" => "/repo",
                          "timestamp" => "2026-05-06T20:00:02Z",
                          "duration_ms" => 12,
                          "exit_status" => 1,
                          "completeness" => "partial"
                        })

               assert {:ok, 1} =
                        Database.query_value(
                          conn,
                          "SELECT COUNT(*) AS value FROM commands WHERE source = 'session'"
                        )

               assert {:ok, [%{command: command, exit_status: 1}]} =
                        Database.query_maps(
                          conn,
                          "SELECT command, exit_status FROM history_view WHERE source = 'session'"
                        )

               assert command =~ "cat ./mix.exs"

               assert {:ok, 2} =
                        Database.query_value(
                          conn,
                          "SELECT COUNT(*) AS value FROM command_paths"
                        )

               assert :ok =
                        Database.exec(
                          conn,
                          """
                          INSERT INTO imports (
                            import_batch_id, source, source_path, imported_at,
                            records_count, warnings_count, report_json
                          )
                          VALUES ('batch-1', 'native', '/tmp/history', '2026-05-06T20:00:00Z', 1, 0, '{}')
                          """
                        )

               report = %{"import_batch_id" => "batch-1", "source" => "native"}

               assert :ok =
                        Projection.insert_import_command(
                          conn,
                          "2026-05-06",
                          %{
                            "command" => "mix test",
                            "cwd" => "/repo",
                            "timestamp" => "2026-05-06T20:00:03Z",
                            "exit_status" => nil
                          },
                          report,
                          1
                        )

               assert :ok =
                        Projection.insert_import_command(
                          conn,
                          "2026-05-06",
                          %{
                            "command" => "mix test --failed",
                            "cwd" => "/repo",
                            "timestamp" => "2026-05-06T20:00:04Z",
                            "exit_status" => 0
                          },
                          report,
                          1
                        )

               assert {:ok, 1} =
                        Database.query_value(
                          conn,
                          "SELECT COUNT(*) AS value FROM commands WHERE source = 'import'"
                        )

               assert {:ok, [%{command: "mix test --failed", exit_status: 0}]} =
                        Database.query_maps(
                          conn,
                          "SELECT command, exit_status FROM history_view WHERE source = 'import'"
                        )

               :ok
             end)
  end
end
