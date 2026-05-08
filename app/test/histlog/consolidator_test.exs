defmodule Histlog.ConsolidatorTest do
  use ExUnit.Case, async: true

  alias Histlog.Consolidator
  alias Histlog.Database
  alias Histlog.Database.Schema
  alias Histlog.Query
  alias Histlog.SessionWriter
  alias Histlog.Storage

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "histlog-consolidator-test-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root, date: ~D[2026-05-06]}
  end

  test "materializes closed sessions into histlog.db", %{
    root: root,
    date: date
  } do
    writer = closed_session!(root, date, "session-1", "git status", "/repo", 0)

    assert {:ok, report} = Consolidator.consolidate(root: root, date: date)

    assert report["sessions_processed"] == [Path.basename(writer.closed_path)]
    assert report["records_written"] == 5
    assert report["exec_records_written"] == 1
    assert report["database_path"] == Storage.database_path(root)
    assert report["schema_reset"] == false
    assert File.exists?(Storage.database_path(root))
    assert database_count(root, "commands") == 1
    assert database_count(root, "processed_sessions") == 1

    assert {:ok, rows} = Query.executions(root: root, date: date, filters: %{command: "git"})
    assert [%{"command" => "git status", "cwd" => "/repo", "exit_status" => 0}] = rows
  end

  test "is idempotent across repeated consolidation runs", %{root: root, date: date} do
    closed_session!(root, date, "session-1", "pwd", "/repo", 0)

    assert {:ok, first} = Consolidator.consolidate(root: root, date: date)
    assert {:ok, second} = Consolidator.consolidate(root: root, date: date)

    assert first["sessions_processed"] != []
    assert second["sessions_processed"] == []
    assert second["records_written"] == 5
    assert second["exec_records_written"] == 1
    assert database_count(root, "commands") == 1
  end

  test "normalizes repeated command text and paths", %{root: root, date: date} do
    closed_session!(root, date, "session-1", "mix test", "/repo", 0)
    closed_session!(root, date, "session-2", "mix test", "/repo", 0)

    assert {:ok, _report} = Consolidator.consolidate(root: root, date: date)

    assert database_count(root, "commands") == 2
    assert database_count(root, "cmd_texts") == 1
    assert database_count(root, "paths") == 1
    assert database_count(root, "sessions") == 2

    assert {:ok, rows} = Query.executions(root: root, date: date, filters: %{command: "mix"})
    assert Enum.map(rows, & &1["command"]) == ["mix test", "mix test"]
  end

  test "materializes all closed session dates when date is omitted", %{root: root, date: date} do
    next_date = Date.add(date, 1)

    closed_session!(root, date, "session-1", "pwd", "/repo/one", 0)
    closed_session!(root, next_date, "session-2", "git status", "/repo/two", 0)

    assert {:ok, report} = Consolidator.consolidate(root: root)

    assert report["date"] == "all"
    assert report["dates"] == [Date.to_iso8601(date), Date.to_iso8601(next_date)]
    assert length(report["sessions_processed"]) == 2
    assert report["records_written"] == 10
    assert report["exec_records_written"] == 2

    assert {:ok, rows} = Query.executions(root: root)
    assert Enum.map(rows, & &1["command"]) == ["pwd", "git status"]
  end

  test "reprocesses a closed session when its checksum changes", %{root: root, date: date} do
    writer = closed_session!(root, date, "session-1", "pwd", "/repo", 0)

    assert {:ok, _first} = Consolidator.consolidate(root: root, date: date)

    writer.closed_path
    |> File.read!()
    |> String.replace("\"command\":\"pwd\"", "\"command\":\"whoami\"")
    |> then(&File.write!(writer.closed_path, &1))

    assert {:ok, second} = Consolidator.consolidate(root: root, date: date)
    assert second["sessions_processed"] == [Path.basename(writer.closed_path)]

    assert {:ok, rows} = Query.executions(root: root, date: date)
    assert [%{"command" => "whoami"}] = rows
    assert database_count(root, "commands") == 1
  end

  test "rebuild rewrites database rows from closed sessions", %{root: root, date: date} do
    closed_session!(root, date, "session-1", "pwd", "/repo", 0)

    assert {:ok, first} = Consolidator.consolidate(root: root, date: date)
    insert_fake_execution!(root, date)
    assert database_count(root, "commands") == 2

    assert {:ok, rebuilt} = Consolidator.consolidate(root: root, date: date, rebuild: true)

    assert rebuilt["sessions_processed"] == first["sessions_processed"]
    assert rebuilt["records_written"] == 5
    assert rebuilt["rebuilt"] == true
    assert database_count(root, "commands") == 1
  end

  test "reports schema reset and rebuilds from canonical sessions", %{root: root, date: date} do
    writer = closed_session!(root, date, "session-1", "pwd", "/repo", 0)

    Database.with_connection(root, fn conn ->
      :ok = Schema.ensure(conn)

      :ok =
        Database.exec(
          conn,
          "UPDATE schema_metadata SET value = 'old' WHERE key = 'schema_version'"
        )
    end)

    assert {:ok, report} = Consolidator.consolidate(root: root, date: date)
    assert report["schema_reset"] == true
    assert report["sessions_processed"] == [Path.basename(writer.closed_path)]

    assert {:ok, rows} = Query.executions(root: root, date: date)
    assert [%{"command" => "pwd"}] = rows
  end

  test "quarantines malformed sessions and continues", %{root: root, date: date} do
    Storage.ensure_layout(root, date)
    bad_path = Path.join(Storage.closed_dir(root, date), "session-bad.ndjson")
    File.write!(bad_path, "{\"not\":\"a histlog event\"}\n")

    assert {:ok, report} = Consolidator.consolidate(root: root, date: date)

    assert [%{"session" => "session-bad.ndjson"}] = report["quarantined_sessions"]
    refute File.exists?(bad_path)
    assert File.exists?(Path.join(Storage.quarantine_dir(root, date), "session-bad.ndjson"))
  end

  defp closed_session!(root, date, session_id, command, cwd, exit_status) do
    {:ok, writer} =
      SessionWriter.start(
        root: root,
        date: date,
        host: "machine",
        process_id: System.unique_integer([:positive]),
        parent_process_id: 1200,
        shell: "zsh",
        session_id: session_id,
        started_at: "2026-05-06T20:00:00Z",
        monotonic_start: System.unique_integer([:positive])
      )

    {:ok, writer, _event} =
      SessionWriter.observe_execution(writer, command, cwd, %{
        "started_at" => "2026-05-06T20:00:01Z",
        "ended_at" => "2026-05-06T20:00:02Z",
        "duration_ms" => 1000,
        "exit_status" => exit_status,
        "completeness" => "complete"
      })

    {:ok, writer, _event} = SessionWriter.close(writer, "2026-05-06T20:00:03Z")
    writer
  end

  defp insert_fake_execution!(root, date) do
    Database.with_connection(root, fn conn ->
      :ok = Schema.ensure(conn)

      Database.exec(
        conn,
        """
        INSERT INTO cmd_texts (command) VALUES ('fake')
        ON CONFLICT(command) DO NOTHING
        """
      )

      {:ok, cmd_text_id} =
        Database.query_value(conn, "SELECT id AS value FROM cmd_texts WHERE command = 'fake'")

      :ok =
        Database.exec(
          conn,
          """
          INSERT INTO sessions (session_uid, session_file, date)
          VALUES ('fake-session', 'fake-session.ndjson', ?)
          ON CONFLICT(session_uid) DO UPDATE SET date = excluded.date
          """,
          [Date.to_iso8601(date)]
        )

      {:ok, session_id} =
        Database.query_value(conn, "SELECT id AS value FROM sessions WHERE session_uid = ?", [
          "fake-session"
        ])

      :ok =
        Database.exec(
          conn,
          """
          INSERT INTO commands (
            session_id, exec_id, date, cmd_text_id, timestamp, duration_ms, exit_status,
            completeness, source
          )
          VALUES (?, 99, ?, ?, '2026-05-06T20:00:00Z', 1, 0, 'complete', 'session')
          """,
          [session_id, Date.to_iso8601(date), cmd_text_id]
        )
    end)
  end

  defp database_count(root, table) do
    {:ok, value} =
      Database.with_connection(root, [mode: :readonly], fn conn ->
        Database.query_value(conn, "SELECT COUNT(*) AS value FROM #{table}")
      end)

    value
  end
end
