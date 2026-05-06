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

  test "reports broken hook-state JSON without appending events", %{root: root} do
    Storage.ensure_layout(root, ~D[2026-05-06])
    File.write!(Hook.state_path(root, "broken"), "{not-json\n")

    assert {:error, {:invalid_hook_state, _reason}} =
             Hook.precmd(root: root, session: "broken", cwd: "/repo", ended_at: "1000")
  end

  test "reports stale missing hook-state without crashing", %{root: root} do
    assert {:error, :enoent} =
             Hook.preexec(root: root, session: "missing", command: "pwd", cwd: "/")
  end

  test "reports invalid persisted writer state without raising", %{root: root} do
    Storage.ensure_layout(root, ~D[2026-05-06])

    File.write!(
      Hook.state_path(root, "bad-writer"),
      JSON.encode!(%{
        "writer" => %{"date" => "2026-05-06", "durability" => "reckless"},
        "pending" => nil
      }) <>
        "\n"
    )

    assert {:error, {:invalid_hook_state, reason}} =
             Hook.precmd(root: root, session: "bad-writer", cwd: "/repo", ended_at: "1000")

    assert reason =~ "invalid durability"
  end

  test "rejects invalid session-start durability without creating hook state", %{root: root} do
    assert {:error, reason} =
             Hook.session_start(
               root: root,
               shell: "fish",
               pid: 1234,
               session_id: "bad-durability",
               durability: "reckless"
             )

    assert reason =~ "invalid durability"
    refute File.exists?(Hook.state_path(root, "bad-durability"))
  end
end
