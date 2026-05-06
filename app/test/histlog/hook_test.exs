defmodule Histlog.HookTest do
  use ExUnit.Case, async: true

  alias Histlog.Hook
  alias Histlog.Storage

  setup do
    root = Path.join(System.tmp_dir!(), "histlog-hook-test-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "records a complete execution across separate hook calls", %{root: root} do
    assert {:ok, session_id} =
             Hook.session_start(
               root: root,
               shell: "zsh",
               pid: 1234,
               ppid: 1200,
               host: "machine",
               date: ~D[2026-05-06],
               started_at: "2026-05-06T20:00:00Z",
               session_id: "session-1"
             )

    assert session_id == "session-1"
    assert File.exists?(Hook.state_path(root, session_id))

    assert :ok =
             Hook.preexec(
               root: root,
               session: session_id,
               command: "mix test",
               cwd: "/repo",
               started_at: "1000"
             )

    assert :ok =
             Hook.precmd(
               root: root,
               session: session_id,
               cwd: "/repo",
               ended_at: "1042",
               exit_status: 0
             )

    assert :ok =
             Hook.session_end(root: root, session: session_id, ended_at: "2026-05-06T20:00:02Z")

    refute File.exists?(Hook.state_path(root, session_id))

    [closed_path] = Path.wildcard(Path.join(Storage.closed_dir(root, ~D[2026-05-06]), "*.ndjson"))
    assert {:ok, events} = Storage.read_events(closed_path)
    execution = Enum.find(events, &(&1["event"] == "execution_observed"))

    assert execution["duration_ms"] == 42
    assert execution["exit_status"] == 0
    assert execution["completeness"] == "complete"
    assert execution["timestamp"] == "1970-01-01T00:00:01.000Z"
    refute Map.has_key?(execution, "started_at")
    refute Map.has_key?(execution, "ended_at")
  end
end
