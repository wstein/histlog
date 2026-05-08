defmodule Histlog.Query do
  @moduledoc """
  Query helpers for materialized command rows plus live session rows.
  """

  alias Histlog.Consolidator
  alias Histlog.CommandText
  alias Histlog.Database
  alias Histlog.Database.Schema
  alias Histlog.PathAnalyzer
  alias Histlog.Storage

  @doc """
  Returns query rows for a date matching simple filters.
  """
  def executions(opts \\ []) do
    root = Storage.root(opts)
    date = Keyword.get(opts, :date)
    filters = Keyword.get(opts, :filters, %{})

    rows =
      root
      |> execution_rows(date)
      |> Enum.filter(&matches?(&1, filters))

    {:ok, rows}
  end

  defp execution_rows(root, nil) do
    root
    |> sqlite_execution_rows(nil)
    |> Kernel.++(live_execution_rows(root, nil))
    |> dedupe_rows()
  end

  defp execution_rows(root, date) do
    root
    |> sqlite_execution_rows(date)
    |> Kernel.++(live_execution_rows(root, date))
    |> dedupe_rows()
  end

  defp sqlite_execution_rows(root, date) do
    path = Storage.database_path(root)

    if File.exists?(path), do: normalize_sqlite_rows(path, read_sqlite_rows(root, date)), else: []
  end

  defp read_sqlite_rows(root, nil) do
    Database.with_connection(root, [mode: :readonly], fn conn ->
      expected_version = Integer.to_string(Schema.version())

      with {:ok, ^expected_version} <- Schema.schema_version(conn),
           {:ok, rows} <-
             Database.query_maps(
               conn,
               """
               SELECT
                 'execution' AS event, command_id, session_id, exec_id, import_batch_id,
                 import_row_index, date, command, cwd, timestamp, duration_ms,
                 exit_status, completeness, shell, host, tty, source,
                 is_private, is_assisted
               FROM history_view
               ORDER BY timestamp ASC, command_id ASC
               """
             ),
           {:ok, path_groups} <- sqlite_path_groups(conn, nil) do
        {:ok,
         rows
         |> Enum.map(&stringify_keys/1)
         |> Enum.map(&CommandText.normalize_row/1)
         |> attach_path_groups(path_groups)}
      else
        {:ok, version} -> {:error, {:schema_version_mismatch, expected_version, version}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp read_sqlite_rows(root, date) do
    Database.with_connection(root, [mode: :readonly], fn conn ->
      expected_version = Integer.to_string(Schema.version())

      with {:ok, ^expected_version} <- Schema.schema_version(conn),
           {:ok, rows} <-
             Database.query_maps(
               conn,
               """
               SELECT
                 'execution' AS event, command_id, session_id, exec_id, import_batch_id,
                 import_row_index, date, command, cwd, timestamp, duration_ms,
                 exit_status, completeness, shell, host, tty, source,
                 is_private, is_assisted
               FROM history_view
               WHERE date = ?
               ORDER BY timestamp ASC, command_id ASC
               """,
               [Date.to_iso8601(date)]
             ),
           {:ok, path_groups} <- sqlite_path_groups(conn, date) do
        {:ok,
         rows
         |> Enum.map(&stringify_keys/1)
         |> Enum.map(&CommandText.normalize_row/1)
         |> attach_path_groups(path_groups)}
      else
        {:ok, version} -> {:error, {:schema_version_mismatch, expected_version, version}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp normalize_sqlite_rows(_path, {:ok, rows}), do: rows

  defp normalize_sqlite_rows(path, {:error, reason}) do
    IO.puts(:stderr, "histlog: skipped sqlite materialization #{path}: #{inspect(reason)}")
    []
  end

  defp live_execution_rows(root, nil) do
    Path.join([root, "sessions", "live", "session-*.ndjson"])
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(&session_execution_rows/1)
  end

  defp live_execution_rows(root, date) do
    root
    |> live_session_paths(date)
    |> Enum.flat_map(&session_execution_rows/1)
  end

  defp live_session_paths(root, date) do
    root
    |> Storage.live_dir(date)
    |> Path.join("session-#{Date.to_iso8601(date)}-*.ndjson")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp session_execution_rows(path) do
    events = read_ndjson_file(path)

    events
    |> Consolidator.derive_execution_rows()
    |> Enum.map(fn row ->
      row
      |> Map.put("source", "live")
      |> CommandText.normalize_row()
      |> Map.put("paths", PathAnalyzer.command_paths(row["command"], row["cwd"]))
    end)
  end

  defp sqlite_path_groups(conn, nil) do
    with {:ok, rows} <-
           Database.query_maps(
             conn,
             """
             SELECT
               command_paths.command_id AS command_id,
               command_paths.arg_position AS arg_position,
               command_paths.original_arg AS original_arg,
               command_paths.resolved_path AS resolved_path,
               command_paths.path_exists AS path_exists,
               command_paths.source AS source,
               paths.path AS path,
               paths.type AS type
             FROM command_paths
             JOIN paths ON command_paths.path_id = paths.id
             ORDER BY command_paths.command_id ASC, command_paths.arg_position ASC
             """
           ) do
      {:ok, group_path_rows(rows)}
    end
  end

  defp sqlite_path_groups(conn, date) do
    with {:ok, rows} <-
           Database.query_maps(
             conn,
             """
             SELECT
               command_paths.command_id AS command_id,
               command_paths.arg_position AS arg_position,
               command_paths.original_arg AS original_arg,
               command_paths.resolved_path AS resolved_path,
               command_paths.path_exists AS path_exists,
               command_paths.source AS source,
               paths.path AS path,
               paths.type AS type
             FROM command_paths
             JOIN paths ON command_paths.path_id = paths.id
             JOIN commands ON command_paths.command_id = commands.id
             WHERE commands.date = ?
             ORDER BY command_paths.command_id ASC, command_paths.arg_position ASC
             """,
             [Date.to_iso8601(date)]
           ) do
      {:ok, group_path_rows(rows)}
    end
  end

  defp group_path_rows(rows) do
    rows
    |> Enum.map(&stringify_keys/1)
    |> Enum.group_by(& &1["command_id"])
    |> Map.new(fn {command_id, paths} ->
      {command_id,
       Enum.map(paths, fn path ->
         %{
           "arg_position" => path["arg_position"],
           "original_arg" => path["original_arg"],
           "resolved_path" => path["resolved_path"],
           "path" => path["path"],
           "exists" => path["path_exists"] == 1,
           "type" => path["type"],
           "source" => path["source"]
         }
       end)}
    end)
  end

  defp attach_path_groups(rows, path_groups) do
    Enum.map(rows, fn row ->
      Map.put(row, "paths", Map.get(path_groups, row["command_id"], []))
    end)
  end

  defp read_ndjson_file(path) do
    path
    |> File.stream!(:line, [])
    |> Stream.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      case JSON.decode(String.trim_trailing(line, "\n")) do
        {:ok, row} ->
          [row]

        {:error, reason} ->
          warn_malformed_row(path, line_number, reason)
          []
      end
    end)
  end

  defp warn_malformed_row(path, line_number, reason) do
    IO.puts(
      :stderr,
      "histlog: skipped malformed record in #{path}:#{line_number}: #{inspect(reason)}"
    )
  end

  defp stringify_keys(row) do
    Map.new(row, fn {key, value} -> {to_string(key), value} end)
  end

  defp dedupe_rows(rows) do
    {_seen, rows} =
      Enum.reduce(rows, {MapSet.new(), []}, fn row, {seen, acc} ->
        key = row_key(row)

        cond do
          is_nil(key) -> {seen, [row | acc]}
          MapSet.member?(seen, key) -> {seen, acc}
          true -> {MapSet.put(seen, key), [row | acc]}
        end
      end)

    Enum.reverse(rows)
  end

  defp row_key(%{"session_id" => session_id, "exec_id" => exec_id})
       when not is_nil(session_id) and not is_nil(exec_id),
       do: {session_id, exec_id}

  defp row_key(_row), do: nil

  defp matches?(row, filters) do
    Enum.all?(filters, fn
      {:command, command} -> String.contains?(row["command"] || "", command)
      {:cwd, cwd} -> row["cwd"] == cwd
      {:exit_status, status} -> row["exit_status"] == status
      {field, value} -> row[to_string(field)] == value
    end)
  end
end
