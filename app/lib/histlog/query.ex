defmodule Histlog.Query do
  @moduledoc """
  Streaming file-based query helpers for derived execution rows.
  """

  alias Histlog.Consolidator
  alias Histlog.Database
  alias Histlog.Database.Schema
  alias Histlog.Storage

  @doc """
  Returns derived execution rows for a date matching simple filters.
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
    |> Kernel.++(imported_execution_rows(root, nil))
    |> dedupe_rows()
  end

  defp execution_rows(root, date) do
    root
    |> sqlite_execution_rows(date)
    |> Kernel.++(live_execution_rows(root, date))
    |> Kernel.++(imported_execution_rows(root, date))
    |> dedupe_rows()
  end

  defp sqlite_execution_rows(root, date) do
    path = Storage.database_path(root)

    if File.exists?(path), do: normalize_sqlite_rows(read_sqlite_rows(root, date)), else: []
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
                 'execution' AS event, session_id, exec_id, command, cwd, timestamp,
                 duration_ms, exit_status, completeness, shell, host, tty, source
               FROM executions
               ORDER BY timestamp ASC, id ASC
               """
             ) do
        rows |> Enum.map(&stringify_keys/1)
      else
        _ -> []
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
                 'execution' AS event, session_id, exec_id, command, cwd, timestamp,
                 duration_ms, exit_status, completeness, shell, host, tty, source
               FROM executions
               WHERE date = ?
               ORDER BY timestamp ASC, id ASC
               """,
               [Date.to_iso8601(date)]
             ) do
        rows |> Enum.map(&stringify_keys/1)
      else
        _ -> []
      end
    end)
  end

  defp normalize_sqlite_rows(rows) when is_list(rows), do: rows
  defp normalize_sqlite_rows(_error), do: []

  defp imported_execution_rows(root, nil) do
    root
    |> Storage.imports_dir()
    |> Path.join("*.ndjson")
    |> Path.wildcard()
    |> Enum.sort()
    |> read_import_files()
  end

  defp imported_execution_rows(root, date) do
    root
    |> Storage.imports_dir()
    |> Path.join("#{Date.to_iso8601(date)}-*.ndjson")
    |> Path.wildcard()
    |> Enum.sort()
    |> read_import_files()
  end

  defp read_import_files(paths) do
    paths
    |> Enum.flat_map(fn path ->
      path
      |> read_ndjson_file()
      |> Enum.filter(&(&1["event"] == "imported_execution"))
      |> Enum.map(&imported_execution_row/1)
    end)
  end

  defp live_execution_rows(root, nil) do
    Path.join([root, "sessions", "live", "*", "*.ndjson"])
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
    |> Path.join("*.ndjson")
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp session_execution_rows(path) do
    events = read_ndjson_file(path)

    events
    |> Consolidator.derive_execution_rows()
    |> Enum.map(&Map.put(&1, "source", "live"))
  end

  defp imported_execution_row(event) do
    %{
      "event" => "execution",
      "session_id" => nil,
      "command" => event["command"],
      "cwd" => event["cwd"],
      "timestamp" => event["timestamp"],
      "duration_ms" => event["duration_ms"],
      "exit_status" => event["exit_status"],
      "completeness" => "imported",
      "source" => "imported"
    }
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
