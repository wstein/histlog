defmodule Histlog.DatabaseSchemaTest do
  use ExUnit.Case, async: true

  alias Histlog.Database
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

               assert {:ok, "4"} = Schema.schema_version(conn)

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
                     ~w(cmd_texts commands hosts imports paths processed_sessions schema_metadata sessions shells ttys) do
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

               :ok
             end)
  end
end
