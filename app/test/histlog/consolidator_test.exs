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

  test "recovers pending materialization before appending new sessions", %{root: root, date: date} do
    Storage.ensure_layout(root, date)

    daily_path = Storage.daily_events_path(root, date)
    exec_path = Storage.daily_exec_path(root, date)
    manifest_path = Storage.manifest_path(root, date)
    daily_stage = daily_path <> ".stage-test"
    exec_stage = exec_path <> ".stage-test"

    daily_content = JSON.encode!(%{"event" => "session_started"}) <> "\n"
    exec_content = JSON.encode!(%{"event" => "execution", "command" => "recovered"}) <> "\n"

    File.write!(daily_path, daily_content)
    File.write!(exec_stage, exec_content)

    manifest = %{
      "schema_version" => 1,
      "date" => Date.to_iso8601(date),
      "sessions_processed" => ["session-recovered.ndjson"],
      "records_written" => 1,
      "exec_records_written" => 1,
      "checksum" => Histlog.Manifest.checksum(daily_content),
      "exec_checksum" => Histlog.Manifest.checksum(exec_content),
      "quarantined_sessions" => []
    }

    pending = %{
      "schema_version" => 1,
      "transaction" => "consolidation",
      "date" => Date.to_iso8601(date),
      "manifest" => manifest,
      "daily" => %{
        "target" => daily_path,
        "tmp" => daily_stage,
        "checksum" => Histlog.Manifest.checksum(daily_content)
      },
      "exec" => %{
        "target" => exec_path,
        "tmp" => exec_stage,
        "checksum" => Histlog.Manifest.checksum(exec_content)
      },
      "manifest_path" => manifest_path
    }

    File.write!(manifest_path <> ".pending", JSON.encode!(pending) <> "\n")

    assert {:ok, recovered} = Consolidator.consolidate(root: root, date: date)
    assert recovered["sessions_processed"] == ["session-recovered.ndjson"]
    assert File.read!(exec_path) == exec_content
    assert JSON.decode!(File.read!(manifest_path))["checksum"] == manifest["checksum"]
    refute File.exists?(manifest_path <> ".pending")
  end

  for {daily_state, exec_state} <- [
        {:stage, :stage},
        {:target, :stage},
        {:stage, :target},
        {:target, :target}
      ] do
    test "recovers pending transaction with daily #{daily_state} and exec #{exec_state}", %{
      root: root,
      date: date
    } do
      %{daily_content: daily_content, exec_content: exec_content, manifest: manifest} =
        write_pending_transaction!(root, date, unquote(daily_state), unquote(exec_state))

      assert {:ok, recovered} = Consolidator.consolidate(root: root, date: date)
      assert recovered["checksum"] == manifest["checksum"]
      assert File.read!(Storage.daily_events_path(root, date)) == daily_content
      assert File.read!(Storage.daily_exec_path(root, date)) == exec_content

      assert JSON.decode!(File.read!(Storage.manifest_path(root, date)))["exec_checksum"] ==
               manifest["exec_checksum"]

      refute File.exists?(Storage.manifest_path(root, date) <> ".pending")
    end
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

  defp write_pending_transaction!(root, date, daily_state, exec_state) do
    Storage.ensure_layout(root, date)

    daily_path = Storage.daily_events_path(root, date)
    exec_path = Storage.daily_exec_path(root, date)
    manifest_path = Storage.manifest_path(root, date)
    daily_stage = daily_path <> ".stage-#{System.unique_integer([:positive])}"
    exec_stage = exec_path <> ".stage-#{System.unique_integer([:positive])}"

    daily_content =
      JSON.encode!(%{"event" => "session_started", "session_id" => "recovered"}) <> "\n"

    exec_content = JSON.encode!(%{"event" => "execution", "command" => "recovered"}) <> "\n"

    write_recovery_file!(daily_state, daily_path, daily_stage, daily_content)
    write_recovery_file!(exec_state, exec_path, exec_stage, exec_content)

    manifest = %{
      "schema_version" => 1,
      "date" => Date.to_iso8601(date),
      "sessions_processed" => ["session-recovered.ndjson"],
      "records_written" => 1,
      "exec_records_written" => 1,
      "checksum" => Histlog.Manifest.checksum(daily_content),
      "exec_checksum" => Histlog.Manifest.checksum(exec_content),
      "quarantined_sessions" => []
    }

    pending = %{
      "schema_version" => 1,
      "transaction" => "consolidation",
      "date" => Date.to_iso8601(date),
      "manifest" => manifest,
      "daily" => %{
        "target" => daily_path,
        "tmp" => daily_stage,
        "checksum" => Histlog.Manifest.checksum(daily_content)
      },
      "exec" => %{
        "target" => exec_path,
        "tmp" => exec_stage,
        "checksum" => Histlog.Manifest.checksum(exec_content)
      },
      "manifest_path" => manifest_path
    }

    File.write!(manifest_path <> ".pending", JSON.encode!(pending) <> "\n")

    %{daily_content: daily_content, exec_content: exec_content, manifest: manifest}
  end

  defp write_recovery_file!(:target, target, _stage, content), do: File.write!(target, content)
  defp write_recovery_file!(:stage, _target, stage, content), do: File.write!(stage, content)
end
