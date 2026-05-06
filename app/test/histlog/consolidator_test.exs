defmodule Histlog.ConsolidatorTest do
  use ExUnit.Case, async: true

  alias Histlog.Consolidator
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

  test "materializes closed sessions into daily event, execution, and manifest files", %{
    root: root,
    date: date
  } do
    writer = closed_session!(root, date, "session-1", "git status", "/repo", 0)

    assert {:ok, manifest} = Consolidator.consolidate(root: root, date: date)

    assert manifest["sessions_processed"] == [Path.basename(writer.closed_path)]
    assert manifest["records_written"] == 5
    assert manifest["exec_records_written"] == 1
    assert manifest["checksum"]
    assert File.exists?(Storage.daily_events_path(root, date))
    assert File.exists?(Storage.daily_exec_path(root, date))
    assert File.exists?(Storage.manifest_path(root, date))

    assert {:ok, rows} = Query.executions(root: root, date: date, filters: %{command: "git"})
    assert [%{"command" => "git status", "cwd" => "/repo", "exit_status" => 0}] = rows
  end

  test "is idempotent across repeated consolidation runs", %{root: root, date: date} do
    closed_session!(root, date, "session-1", "pwd", "/repo", 0)

    assert {:ok, first} = Consolidator.consolidate(root: root, date: date)
    assert {:ok, second} = Consolidator.consolidate(root: root, date: date)

    assert first == second

    assert Storage.daily_events_path(root, date)
           |> File.read!()
           |> String.split("\n", trim: true)
           |> length() == 5
  end

  test "rebuild rewrites daily files from closed sessions", %{root: root, date: date} do
    closed_session!(root, date, "session-1", "pwd", "/repo", 0)

    assert {:ok, first} = Consolidator.consolidate(root: root, date: date)
    daily_path = Storage.daily_events_path(root, date)
    File.write!(daily_path, "corrupted\n")

    assert {:ok, rebuilt} = Consolidator.consolidate(root: root, date: date, rebuild: true)

    refute first["checksum"] == Histlog.Manifest.checksum("corrupted\n")
    assert rebuilt["sessions_processed"] == first["sessions_processed"]
    assert rebuilt["records_written"] == 5
    assert rebuilt["rebuilt"] == true

    assert daily_path
           |> File.read!()
           |> String.split("\n", trim: true)
           |> length() == 5
  end

  test "quarantines malformed sessions and continues", %{root: root, date: date} do
    Storage.ensure_layout(root, date)
    bad_path = Path.join(Storage.closed_dir(root, date), "session-bad.ndjson")
    File.write!(bad_path, "{\"not\":\"a histlog event\"}\n")

    assert {:ok, manifest} = Consolidator.consolidate(root: root, date: date)

    assert [%{"session" => "session-bad.ndjson"}] = manifest["quarantined_sessions"]
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
end
