defmodule Histlog.Database do
  @moduledoc """
  Small SQLite boundary for histlog materialized query data.
  """

  alias Exqlite.Sqlite3
  alias Histlog.Storage

  def path(root), do: Storage.database_path(root)

  def open(root, opts \\ []) do
    database_path = path(root)
    maybe_prepare_parent(database_path, opts)
    Sqlite3.open(database_path, opts)
  end

  def close(conn), do: Sqlite3.close(conn)

  def with_connection(root, opts \\ [], fun) when is_function(fun, 1) do
    with {:ok, conn} <- open(root, opts) do
      try do
        fun.(conn)
      after
        close(conn)
      end
    end
  end

  def transaction(conn, fun) when is_function(fun, 0) do
    with :ok <- Sqlite3.execute(conn, "BEGIN IMMEDIATE") do
      case fun.() do
        {:ok, value} ->
          with :ok <- Sqlite3.execute(conn, "COMMIT") do
            {:ok, value}
          end

        :ok ->
          with :ok <- Sqlite3.execute(conn, "COMMIT") do
            :ok
          end

        {:error, reason} ->
          Sqlite3.execute(conn, "ROLLBACK")
          {:error, reason}
      end
    end
  rescue
    exception ->
      Sqlite3.execute(conn, "ROLLBACK")
      reraise exception, __STACKTRACE__
  end

  def execute(conn, sql), do: Sqlite3.execute(conn, sql)

  def exec(conn, sql, params \\ []) do
    with {:ok, statement} <- Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Sqlite3.bind(statement, params),
             :done <- Sqlite3.step(conn, statement) do
          :ok
        end
      after
        Sqlite3.release(conn, statement)
      end
    end
  end

  def query_maps(conn, sql, params \\ []) do
    with {:ok, statement} <- Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Sqlite3.bind(statement, params),
             {:ok, columns} <- Sqlite3.columns(conn, statement),
             {:ok, rows} <- Sqlite3.fetch_all(conn, statement) do
          {:ok, Enum.map(rows, &row_to_map(columns, &1))}
        end
      after
        Sqlite3.release(conn, statement)
      end
    end
  end

  def query_value(conn, sql, params \\ []) do
    with {:ok, [%{value: value}]} <- query_maps(conn, sql, params) do
      {:ok, value}
    else
      {:ok, []} -> {:ok, nil}
      other -> other
    end
  end

  defp row_to_map(columns, row) do
    columns
    |> Enum.zip(row)
    |> Map.new(fn {column, value} -> {String.to_atom(column), value} end)
  end

  defp maybe_prepare_parent(database_path, opts) do
    unless Keyword.get(opts, :mode) == :readonly do
      File.mkdir_p!(Path.dirname(database_path))
    end
  end
end
