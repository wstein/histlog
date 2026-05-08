defmodule Histlog.SessionLayoutMigrationScriptTest do
  use ExUnit.Case, async: false

  @repo_root Path.expand("../../..", __DIR__)

  test "standalone script flattens legacy dated session directories" do
    root = tmp_dir()

    legacy_closed =
      Path.join(root, "sessions/closed/2026-05-08/session-Mac-123--456.ndjson")

    legacy_live =
      Path.join(root, "sessions/live/2026-05-07/session-2026-05-07-Mac-999--111.ndjson")

    File.mkdir_p!(Path.dirname(legacy_closed))
    File.mkdir_p!(Path.dirname(legacy_live))
    File.write!(legacy_closed, "{\"event\":\"session_started\"}\n")
    File.write!(legacy_live, "{\"event\":\"session_started\"}\n")

    {dry_output, dry_status} =
      System.cmd("elixir", ["scripts/flatten-session-layout.exs", "--root", root, "--dry-run"],
        cd: @repo_root,
        stderr_to_stdout: true
      )

    assert dry_status == 0, dry_output
    assert {:ok, dry_report} = JSON.decode(dry_output)
    assert dry_report["dry_run"] == true
    assert dry_report["moves_count"] == 2
    assert File.exists?(legacy_closed)

    {output, status} =
      System.cmd("elixir", ["scripts/flatten-session-layout.exs", "--root", root],
        cd: @repo_root,
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert {:ok, report} = JSON.decode(output)
    assert report["dry_run"] == false
    assert report["moves_count"] == 2

    flat_closed = Path.join(root, "sessions/closed/session-2026-05-08-Mac-123--456.ndjson")
    flat_live = Path.join(root, "sessions/live/session-2026-05-07-Mac-999--111.ndjson")

    refute File.exists?(legacy_closed)
    refute File.exists?(legacy_live)
    assert File.exists?(flat_closed)
    assert File.exists?(flat_live)
    refute File.exists?(Path.join(root, "sessions/closed/2026-05-08"))
    refute File.exists?(Path.join(root, "sessions/live/2026-05-07"))
  end

  defp tmp_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "histlog-session-layout-migration-test-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
