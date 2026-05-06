defmodule Histlog.SessionWriterTest do
  use ExUnit.Case, async: true

  alias Histlog.Schema
  alias Histlog.SessionWriter
  alias Histlog.Storage

  setup do
    root = Path.join(System.tmp_dir!(), "histlog-test-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "writes one session file in live and moves it to closed on close", %{root: root} do
    date = ~D[2026-05-06]

    assert {:ok, writer} =
             SessionWriter.start(
               root: root,
               date: date,
               host: "machine",
               process_id: 1234,
               parent_process_id: 1200,
               shell: "zsh",
               session_id: "session-1",
               started_at: "2026-05-06T20:00:00Z",
               monotonic_start: 12_345
             )

    assert File.exists?(writer.live_path)

    assert {:ok, writer, _event} =
             SessionWriter.observe_execution(writer, "ls -alh", "/home/user/work", %{
               "started_at" => "2026-05-06T20:00:01Z",
               "ended_at" => "2026-05-06T20:00:02Z",
               "duration_ms" => 1000,
               "exit_status" => 0,
               "completeness" => "complete"
             })

    assert {:ok, writer, _event} = SessionWriter.close(writer, "2026-05-06T20:00:03Z")

    refute File.exists?(writer.live_path)
    assert File.exists?(writer.closed_path)

    assert {:ok, events} = Storage.read_events(writer.closed_path)
    assert :ok = Schema.validate_sequence(events)

    assert Enum.map(events, & &1["event"]) == [
             "session_started",
             "command_defined",
             "folder_defined",
             "execution_observed",
             "session_ended"
           ]

    [session_started, command_defined, _folder_defined, execution_observed, session_ended] =
      events

    assert session_started["session_id"] == "session-1"
    refute Map.has_key?(command_defined, "session_id")
    refute Map.has_key?(execution_observed, "session_id")
    refute Map.has_key?(execution_observed, "recorded_at")
    refute Map.has_key?(execution_observed, "started_at")
    refute Map.has_key?(execution_observed, "ended_at")
    assert execution_observed["timestamp"] == "2026-05-06T20:00:01Z"
    assert session_ended["timestamp"] == "2026-05-06T20:00:03Z"
  end

  test "deduplicates commands and folders within a session", %{root: root} do
    assert {:ok, writer} =
             SessionWriter.start(
               root: root,
               host: "machine",
               process_id: 1234,
               parent_process_id: 1200,
               shell: "zsh",
               session_id: "session-1",
               monotonic_start: 12_345
             )

    assert {:ok, writer, first_command_id} = SessionWriter.define_command(writer, "pwd")
    assert {:ok, writer, second_command_id} = SessionWriter.define_command(writer, "pwd")
    assert {:ok, writer, first_folder_id} = SessionWriter.define_folder(writer, "/tmp")
    assert {:ok, writer, second_folder_id} = SessionWriter.define_folder(writer, "/tmp")

    assert first_command_id == second_command_id
    assert first_folder_id == second_folder_id
    assert writer.seq == 3
  end
end
