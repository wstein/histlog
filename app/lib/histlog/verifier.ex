defmodule Histlog.Verifier do
  @moduledoc """
  Verification for the SQLite materialized query database.
  """

  alias Histlog.Database
  alias Histlog.Database.Schema
  alias Histlog.Storage

  @tables Histlog.Database.Schema.tables()

  @doc """
  Verifies database schema and consolidation checkpoints for a date.
  """
  def verify(opts \\ []) do
    root = Storage.root(opts)
    date = Keyword.get(opts, :date, Date.utc_today())
    path = Storage.database_path(root)

    if File.exists?(path) do
      report =
        Database.with_connection(root, [mode: :readonly], fn conn ->
          build_report(conn, path, date)
        end)

      case report do
        %{"ok" => true} -> {:ok, report}
        %{"ok" => false} -> {:error, report}
        {:error, reason} -> {:error, database_error_report(path, date, reason)}
      end
    else
      {:error, database_missing_report(path, date)}
    end
  end

  defp build_report(conn, path, date) do
    table_checks = table_checks(conn)
    schema = schema_check(conn, table_checks["schema_metadata"]["ok"])

    counts =
      count_checks(conn, date, Enum.all?(table_checks, fn {_name, check} -> check["ok"] end))

    errors =
      []
      |> add_schema_errors(schema)
      |> add_table_errors(table_checks)
      |> add_count_errors(counts)

    %{
      "ok" => errors == [],
      "date" => Date.to_iso8601(date),
      "database_path" => path,
      "errors" => errors,
      "checks" => %{
        "database" => %{"ok" => true, "path" => path},
        "schema" => schema,
        "tables" => table_checks,
        "counts" => counts
      }
    }
  end

  defp table_checks(conn) do
    Map.new(@tables, fn table ->
      exists? =
        case Database.query_value(
               conn,
               "SELECT COUNT(*) AS value FROM sqlite_master WHERE type = 'table' AND name = ?",
               [table]
             ) do
          {:ok, 1} -> true
          _ -> false
        end

      {table, %{"ok" => exists?, "table" => table}}
    end)
  end

  defp schema_check(_conn, false) do
    %{"ok" => false, "expected" => Schema.version(), "actual" => nil}
  end

  defp schema_check(conn, true) do
    expected = Integer.to_string(Schema.version())

    actual =
      case Schema.schema_version(conn) do
        {:ok, value} -> value
        _ -> nil
      end

    %{
      "ok" => actual == expected,
      "expected" => expected,
      "actual" => actual
    }
  end

  defp count_checks(_conn, _date, false) do
    %{
      "ok" => false,
      "processed_sessions" => nil,
      "sessions" => nil,
      "processed_command_rows" => nil,
      "commands" => nil
    }
  end

  defp count_checks(conn, date, true) do
    date = Date.to_iso8601(date)

    {:ok, processed_sessions} =
      count(conn, "SELECT COUNT(*) FROM processed_sessions WHERE date = ?", [date])

    {:ok, sessions} = count(conn, "SELECT COUNT(*) FROM sessions WHERE date = ?", [date])

    {:ok, processed_command_rows} =
      count(
        conn,
        "SELECT COALESCE(SUM(commands_count), 0) FROM processed_sessions WHERE date = ?",
        [
          date
        ]
      )

    {:ok, commands} =
      count(conn, "SELECT COUNT(*) FROM commands WHERE date = ? AND source = 'session'", [date])

    %{
      "ok" => processed_sessions == sessions and processed_command_rows == commands,
      "processed_sessions" => processed_sessions,
      "sessions" => sessions,
      "processed_command_rows" => processed_command_rows,
      "commands" => commands
    }
  end

  defp count(conn, sql, params) do
    Database.query_value(conn, "SELECT (#{sql}) AS value", params)
  end

  defp add_schema_errors(errors, %{"ok" => true}), do: errors

  defp add_schema_errors(errors, check) do
    errors ++ ["schema: expected #{inspect(check["expected"])} got #{inspect(check["actual"])}"]
  end

  defp add_table_errors(errors, table_checks) do
    missing =
      table_checks
      |> Enum.reject(fn {_name, check} -> check["ok"] end)
      |> Enum.map(fn {name, _check} -> "table_missing: #{name}" end)

    errors ++ missing
  end

  defp add_count_errors(errors, %{"ok" => true}), do: errors

  defp add_count_errors(errors, counts) do
    errors ++
      [
        "counts: processed_sessions=#{inspect(counts["processed_sessions"])} sessions=#{inspect(counts["sessions"])} processed_command_rows=#{inspect(counts["processed_command_rows"])} commands=#{inspect(counts["commands"])}"
      ]
  end

  defp database_missing_report(path, date) do
    %{
      "ok" => false,
      "date" => Date.to_iso8601(date),
      "database_path" => path,
      "errors" => ["database_missing"],
      "checks" => %{
        "database" => %{"ok" => false, "path" => path, "error" => "missing"}
      }
    }
  end

  defp database_error_report(path, date, reason) do
    %{
      "ok" => false,
      "date" => Date.to_iso8601(date),
      "database_path" => path,
      "errors" => [inspect(reason)],
      "checks" => %{
        "database" => %{"ok" => false, "path" => path, "error" => inspect(reason)}
      }
    }
  end
end
