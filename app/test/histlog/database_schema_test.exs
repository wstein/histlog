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

               assert {:ok, "2"} = Schema.schema_version(conn)

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

               for table <- ~w(executions processed_sessions schema_metadata sessions) do
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

               :ok
             end)
  end
end
