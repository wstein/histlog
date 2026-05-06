defmodule Histlog.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Histlog.CLI
  alias Histlog.SessionWriter

  @fixtures Path.expand("../fixtures/import", __DIR__)

  setup do
    root = Path.join(System.tmp_dir!(), "histlog-cli-test-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root, date: ~D[2026-05-06]}
  end

  test "consolidate and query commands emit NDJSON-compatible output", %{root: root, date: date} do
    {:ok, writer} =
      SessionWriter.start(
        root: root,
        date: date,
        host: "machine",
        process_id: 1234,
        parent_process_id: 1200,
        shell: "zsh",
        session_id: "session-1",
        monotonic_start: 12_345
      )

    {:ok, writer, _event} =
      SessionWriter.observe_execution(writer, "mix test", "/repo", %{
        "started_at" => "2026-05-06T20:00:00Z",
        "ended_at" => "2026-05-06T20:00:01Z",
        "duration_ms" => 1000,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, _writer, _event} = SessionWriter.close(writer, "2026-05-06T20:00:02Z")

    manifest_output =
      capture_io(fn ->
        assert :ok = CLI.run(["consolidate", "--root", root, "--date", Date.to_iso8601(date)])
      end)

    assert JSON.decode!(manifest_output)["records_written"] == 5

    query_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "query",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--command",
                   "mix"
                 ])
      end)

    assert [%{"command" => "mix test"}] =
             query_output
             |> String.split("\n", trim: true)
             |> Enum.map(&JSON.decode!/1)
  end

  test "import command converts shell history fixtures to native import NDJSON", %{
    root: root,
    date: date
  } do
    source_path = Path.join(@fixtures, "zsh_history")

    output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "import",
                   source_path,
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--source",
                   "zsh_history",
                   "--session-id",
                   "import-session",
                   "--import-batch-id",
                   "batch-1"
                 ])
      end)

    destination = String.trim(output)
    assert File.exists?(destination)

    events =
      destination
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

    assert Enum.map(events, & &1["event"]) == [
             "import_batch_started",
             "imported_execution",
             "imported_execution",
             "imported_execution",
             "import_batch_finished"
           ]
  end
end
