defmodule Histlog.Database.Maintenance do
  @moduledoc """
  Read-only maintenance diagnostics for the derived SQLite projection.
  """

  alias Histlog.Database
  alias Histlog.Storage

  def diagnose(opts \\ []) do
    root = Storage.root(opts)
    path = Storage.database_path(root)

    if File.exists?(path) do
      case Database.with_connection(root, [mode: :readonly], &build_report/1) do
        {:error, reason} -> {:error, error_report(path, reason)}
        report -> {:ok, Map.put(report, "path", path)}
      end
    else
      {:error, %{"ok" => false, "path" => path, "errors" => ["database_missing"]}}
    end
  end

  defp build_report(conn) do
    integrity = integrity_check(conn)
    orphans = orphan_checks(conn)
    errors = integrity_errors(integrity) ++ orphan_errors(orphans)

    %{
      "ok" => errors == [],
      "errors" => errors,
      "checks" => %{
        "integrity" => integrity,
        "orphans" => orphans
      }
    }
  end

  defp integrity_check(conn) do
    case Database.query_maps(conn, "PRAGMA integrity_check") do
      {:ok, rows} ->
        values = Enum.map(rows, &Map.get(&1, :integrity_check))
        %{"ok" => values == ["ok"], "result" => values}

      {:error, reason} ->
        %{"ok" => false, "error" => inspect(reason), "result" => []}
    end
  end

  defp orphan_checks(conn) do
    checks = %{
      "command_paths_without_commands" =>
        count(conn, """
        SELECT COUNT(*)
        FROM command_paths
        LEFT JOIN commands ON command_paths.command_id = commands.id
        WHERE commands.id IS NULL
        """),
      "commands_without_text" =>
        count(conn, """
        SELECT COUNT(*)
        FROM commands
        LEFT JOIN cmd_texts ON commands.cmd_text_id = cmd_texts.id
        WHERE cmd_texts.id IS NULL
        """),
      "session_commands_without_session" =>
        count(conn, """
        SELECT COUNT(*)
        FROM commands
        LEFT JOIN sessions ON commands.session_id = sessions.id
        WHERE commands.source = 'session' AND sessions.id IS NULL
        """),
      "import_commands_without_import" =>
        count(conn, """
        SELECT COUNT(*)
        FROM commands
        LEFT JOIN imports ON commands.import_batch_id = imports.import_batch_id
        WHERE commands.source = 'import' AND imports.import_batch_id IS NULL
        """)
    }

    %{
      "ok" => Enum.all?(checks, fn {_name, value} -> value == 0 end),
      "counts" => checks
    }
  end

  defp count(conn, sql) do
    case Database.query_value(conn, "SELECT (#{sql}) AS value") do
      {:ok, value} when is_integer(value) -> value
      _other -> nil
    end
  end

  defp integrity_errors(%{"ok" => true}), do: []
  defp integrity_errors(%{"error" => error}), do: ["integrity_check: #{error}"]
  defp integrity_errors(%{"result" => result}), do: ["integrity_check: #{inspect(result)}"]

  defp orphan_errors(%{"ok" => true}), do: []

  defp orphan_errors(%{"counts" => counts}) do
    counts
    |> Enum.reject(fn {_name, value} -> value == 0 end)
    |> Enum.map(fn {name, value} -> "orphan_check: #{name}=#{inspect(value)}" end)
  end

  defp error_report(path, reason) do
    %{
      "ok" => false,
      "path" => path,
      "errors" => [inspect(reason)],
      "checks" => %{}
    }
  end
end
