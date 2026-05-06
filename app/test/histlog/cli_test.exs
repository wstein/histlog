defmodule Histlog.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Histlog.CLI
  alias Histlog.Consolidator
  alias Histlog.SessionWriter
  alias Histlog.Storage

  @fixtures Path.expand("../fixtures/import", __DIR__)

  setup do
    root = Path.join(System.tmp_dir!(), "histlog-cli-test-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root, date: ~D[2026-05-06]}
  end

  test "consolidate and query commands emit human-readable table output", %{
    root: root,
    date: date
  } do
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

    assert query_output =~ "\e[38;5;141mSess\e[0m"
    assert query_output =~ "\e[38;5;84m✓   \e[0m"

    assert strip_ansi(query_output) =~
             "0001 #{local_display("2026-05-06T20:00:00Z")}    1.000s ✓    mix test"
  end

  test "query command can emit JSON output explicitly", %{root: root, date: date} do
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
        "timestamp" => "2026-05-06T20:00:00Z",
        "duration_ms" => 1000,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, _writer, _event} = SessionWriter.close(writer, "2026-05-06T20:00:02Z")

    capture_io(fn ->
      assert :ok = CLI.run(["consolidate", "--root", root, "--date", Date.to_iso8601(date)])
    end)

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
                   "mix",
                   "--json"
                 ])
      end)

    assert [%{"command" => "mix test"}] = JSON.decode!(query_output)
  end

  test "query command rejects internal storage formats", %{root: root, date: date} do
    assert {:error, "unsupported query format \"ndjson\""} =
             CLI.run([
               "query",
               "--root",
               root,
               "--date",
               Date.to_iso8601(date),
               "--format",
               "ndjson"
             ])
  end

  test "query help documents rich public interface without storage formats" do
    output =
      capture_io(fn ->
        assert :ok = CLI.run(["query", "--help"])
      end)

    assert output =~ "Usage: histlog query [search] [options]"
    assert output =~ "--failed"
    assert output =~ "--json"
    refute output =~ "ndjson"
  end

  test "query searches all dates by default and supports public filters", %{
    root: root,
    date: date
  } do
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
        "timestamp" => "2026-05-06T20:00:00Z",
        "duration_ms" => 1500,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, writer, _event} =
      SessionWriter.observe_execution(writer, "mix format", "/repo", %{
        "timestamp" => "2026-05-06T20:01:00Z",
        "duration_ms" => 50,
        "exit_status" => 1,
        "completeness" => "complete"
      })

    {:ok, _writer, _event} = SessionWriter.close(writer, "2026-05-06T20:02:00Z")

    capture_io(fn ->
      assert :ok = CLI.run(["consolidate", "--root", root, "--date", Date.to_iso8601(date)])
    end)

    output =
      capture_io(fn ->
        assert :ok = CLI.run(["query", "mix", "--root", root, "--failed", "--plain"])
      end)

    assert output == "mix format\n"
  end

  test "query table and time filters use local time", %{root: root, date: date} do
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
      SessionWriter.observe_execution(writer, "local clock", "/repo", %{
        "timestamp" => "2026-05-06T20:00:00Z",
        "duration_ms" => 10,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, _writer, _event} = SessionWriter.close(writer, "2026-05-06T20:00:01Z")

    capture_io(fn ->
      assert :ok = CLI.run(["consolidate", "--root", root, "--date", Date.to_iso8601(date)])
    end)

    local_time = local_display("2026-05-06T20:00:00Z")

    table_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "query",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--command",
                   "local clock"
                 ])
      end)

    assert strip_ansi(table_output) =~ local_time

    plain_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "query",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--since",
                   local_time,
                   "--before",
                   local_time,
                   "--plain"
                 ])
      end)

    assert plain_output == "local clock\n"
  end

  test "paths command summarizes cwd and path-like arguments", %{root: root, date: date} do
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
      SessionWriter.observe_execution(writer, "cat ./mix.exs /tmp/file", "/repo/app", %{
        "timestamp" => "2026-05-06T20:00:00Z",
        "duration_ms" => 10,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, writer, _event} =
      SessionWriter.observe_execution(writer, "ls ..", "/repo/app", %{
        "timestamp" => "2026-05-06T20:00:01Z",
        "duration_ms" => 10,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, _writer, _event} = SessionWriter.close(writer, "2026-05-06T20:00:01Z")

    capture_io(fn ->
      assert :ok = CLI.run(["consolidate", "--root", root, "--date", Date.to_iso8601(date)])
    end)

    output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "paths",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--json"
                 ])
      end)

    rows = JSON.decode!(output)
    assert %{"exec" => 2, "args" => 0, "path" => "/repo/app"} in rows
    assert %{"exec" => 0, "args" => 1, "path" => "/repo/app/mix.exs"} in rows
    assert %{"exec" => 0, "args" => 1, "path" => "/tmp/file"} in rows
    assert %{"exec" => 0, "args" => 1, "path" => "/repo"} in rows
  end

  test "unknown commands return structured errors" do
    assert {:error, {:unknown_command, "wat"}} = CLI.run(["wat"])
  end

  test "empty query command still emits table headers", %{root: root, date: date} do
    query_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "query",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date)
                 ])
      end)

    assert query_output ==
             "\e[38;5;141mSess\e[0m \e[38;5;14mTimestamp\e[0m          \e[33m Duration\e[0m \e[38;5;84mExit\e[0m Command\n--------------------------------------------------\n"
  end

  test "consolidate command accepts rebuild flag", %{root: root, date: date} do
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
      SessionWriter.observe_execution(writer, "pwd", "/repo", %{
        "timestamp" => "2026-05-06T20:00:00Z",
        "duration_ms" => 10,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, _writer, _event} = SessionWriter.close(writer, "2026-05-06T20:00:01Z")

    output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "consolidate",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--rebuild"
                 ])
      end)

    assert %{"rebuilt" => true, "records_written" => 5} = JSON.decode!(output)
  end

  test "query and tail include currently live session files", %{root: root, date: date} do
    {:ok, writer} =
      SessionWriter.start(
        root: root,
        date: date,
        host: "machine",
        process_id: 1234,
        parent_process_id: 1200,
        shell: "fish",
        session_id: "session-live",
        monotonic_start: 12_345
      )

    assert {:ok, _writer, _event} =
             SessionWriter.observe_execution(writer, "histlog query", "/repo", %{
               "timestamp" => "2026-05-06T20:00:00Z",
               "duration_ms" => 10,
               "exit_status" => 0,
               "completeness" => "complete"
             })

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
                   "histlog",
                   "--json"
                 ])
      end)

    assert [%{"command" => "histlog query", "source" => "live"}] = JSON.decode!(query_output)

    live_default_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "query",
                   "--root",
                   root,
                   "--command",
                   "histlog",
                   "--plain"
                 ])
      end)

    assert live_default_output == "histlog query\n"

    tail_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "tail",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--count",
                   "1"
                 ])
      end)

    assert [%{"event" => "execution_observed"}] =
             tail_output
             |> String.split("\n", trim: true)
             |> Enum.map(&JSON.decode!/1)
  end

  test "verify command reports materialization integrity", %{root: root, date: date} do
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
      SessionWriter.observe_execution(writer, "pwd", "/repo", %{
        "timestamp" => "2026-05-06T20:00:00Z",
        "duration_ms" => 10,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, _writer, _event} = SessionWriter.close(writer, "2026-05-06T20:00:01Z")
    assert {:ok, _manifest} = Consolidator.consolidate(root: root, date: date)

    output =
      capture_io(fn ->
        assert :ok = CLI.run(["verify", "--root", root, "--date", Date.to_iso8601(date)])
      end)

    assert %{"ok" => true, "checks" => %{"daily" => %{"ok" => true}}} = JSON.decode!(output)

    File.write!(Storage.daily_events_path(root, date), "corrupted\n")

    output =
      capture_io(fn ->
        assert {:error, "verification failed"} =
                 CLI.run(["verify", "--root", root, "--date", Date.to_iso8601(date)])
      end)

    assert %{"ok" => false, "errors" => errors} = JSON.decode!(output)
    assert Enum.any?(errors, &String.contains?(&1, "daily"))
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

  test "init command prints shell integration without aliases by default" do
    output =
      capture_io(fn ->
        assert :ok = CLI.run(["init", "zsh"])
      end)

    assert output =~ "histlog zsh integration"
    assert output =~ "\"$HISTLOG_BIN\" hook session-start --root \"$HISTLOG_ROOT\" --shell zsh"
    refute output =~ "alias hl="
  end

  test "init command accepts an explicit binary path" do
    output =
      capture_io(fn ->
        assert :ok = CLI.run(["init", "zsh", "--binary", "/opt/histlog/bin/histlog"])
      end)

    assert output =~ "HISTLOG_BIN=\"${HISTLOG_BIN:-/opt/histlog/bin/histlog}\""
  end

  test "init command accepts a default durability mode" do
    output =
      capture_io(fn ->
        assert :ok = CLI.run(["init", "zsh", "--durability", "fast"])
      end)

    assert output =~ "HISTLOG_DURABILITY=\"${HISTLOG_DURABILITY:-fast}\""
  end

  test "init command prints aliases only when requested" do
    output =
      capture_io(fn ->
        assert :ok = CLI.run(["init", "bash", "--aliases"])
      end)

    assert output =~ "histlog bash integration"
    assert output =~ "alias hl='histlog'"
  end

  test "completions command prints shell completion code" do
    output =
      capture_io(fn ->
        assert :ok = CLI.run(["completions", "fish"])
      end)

    assert output =~ "complete -c histlog"
    assert output =~ "Diagnose setup"
  end

  test "doctor emits JSON diagnostics" do
    output =
      capture_io(fn ->
        assert :ok = CLI.run(["doctor", "zsh"])
      end)

    assert %{"shell" => "zsh", "checks" => checks} = JSON.decode!(output)
    assert Enum.any?(checks, &(&1["check"] == "shell" and &1["status"] == "ok"))
  end

  test "command option parsing reports errors" do
    assert {:error, error} = CLI.run(["query", "--unknown"])
    assert error =~ "invalid options"

    assert {:error, error} = CLI.run(["query", "--date", "not-a-date"])
    assert error =~ "invalid date"

    assert {:error, error} = CLI.run(["tail", "--count", "many"])
    assert error =~ "invalid options"

    assert {:error, error} = CLI.run(["init", "zsh", "bash"])
    assert error =~ "unexpected arguments"
  end

  test "command aliases parse through OptionParser" do
    output =
      capture_io(fn ->
        assert :ok = CLI.run(["tail", "-r", "/tmp/histlog-missing", "-d", "2026-05-06"])
      end)

    assert output == ""
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")

  defp local_display(timestamp) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(timestamp)

    datetime
    |> DateTime.to_unix(:second)
    |> :calendar.system_time_to_local_time(:second)
    |> then(fn {{year, month, day}, {hour, minute, second}} ->
      "#{pad(year, 4)}-#{pad(month, 2)}-#{pad(day, 2)} #{pad(hour, 2)}:#{pad(minute, 2)}:#{pad(second, 2)}"
    end)
  end

  defp pad(value, count), do: value |> Integer.to_string() |> String.pad_leading(count, "0")
end
