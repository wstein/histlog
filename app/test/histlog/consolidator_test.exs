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
    assert File.exists?(Storage.database_path(root))
    assert database_count(root, "executions") == 1
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
    assert database_count(root, "executions") == 1
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
    assert database_count(root, "executions") == 1
  end

  test "rebuild rewrites database rows from closed sessions", %{root: root, date: date} do
    closed_session!(root, date, "session-1", "pwd", "/repo", 0)

    assert {:ok, first} = Consolidator.consolidate(root: root, date: date)
    insert_fake_execution!(root, date)
    assert database_count(root, "executions") == 2

    assert {:ok, rebuilt} = Consolidator.consolidate(root: root, date: date, rebuild: true)

    assert rebuilt["sessions_processed"] == first["sessions_processed"]
    assert rebuilt["records_written"] == 5
    assert rebuilt["rebuilt"] == true
    assert database_count(root, "executions") == 1
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
        INSERT INTO executions (
          session_id, exec_id, date, command, cwd, timestamp, duration_ms,
          exit_status, completeness, shell, host, tty, source
        )
        VALUES ('fake-session', 999, ?, 'fake', '/tmp', '2026-05-06T20:00:00Z',
          1, 0, 'complete', 'zsh', 'machine', NULL, 'sqlite')
        """,
        [Date.to_iso8601(date)]
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
