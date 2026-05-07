defmodule Histlog.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Histlog.CLI
  alias Histlog.Consolidator
  alias Histlog.Database
  alias Histlog.Database.Schema
  alias Histlog.SessionWriter

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

    report_output =
      capture_io(fn ->
        assert :ok = CLI.run(["consolidate", "--root", root, "--date", Date.to_iso8601(date)])
      end)

    assert JSON.decode!(report_output)["records_written"] == 5

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

  test "export command emits derived query rows as ndjson", %{root: root, date: date} do
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
    assert {:ok, _report} = Consolidator.consolidate(root: root, date: date)

    output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "export",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--format",
                   "ndjson"
                 ])
      end)

    assert [%{"command" => "mix test", "event" => "execution"}] =
             output
             |> String.split("\n", trim: true)
             |> Enum.map(&JSON.decode!/1)

    assert {:error, "unsupported export format \"json\""} =
             CLI.run([
               "export",
               "--root",
               root,
               "--date",
               Date.to_iso8601(date),
               "--format",
               "json"
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

  test "top-level help flags and help forwarding match public CLI expectations" do
    help_output =
      capture_io(fn ->
        assert :ok = CLI.run(["--help"])
      end)

    assert help_output =~ "Usage: histlog <command> [options]"
    assert help_output =~ "query       - Flexible query"
    assert help_output =~ "commands    - Summarize command usage"
    assert help_output =~ "info        - Show runtime paths and environment"
    assert help_output =~ "histlog help <command>"
    refute help_output =~ "hook"

    short_help_output =
      capture_io(fn ->
        assert :ok = CLI.run(["-h"])
      end)

    assert short_help_output == help_output

    query_help_output =
      capture_io(fn ->
        assert :ok = CLI.run(["help", "query"])
      end)

    assert query_help_output =~ "Usage: histlog query [search] [options]"
    assert query_help_output =~ "--duration DURATION"
    refute query_help_output =~ "histlog commands:"

    commands_help_output =
      capture_io(fn ->
        assert :ok = CLI.run(["help", "commands"])
      end)

    assert commands_help_output =~ "Usage: histlog commands [search] [options]"
    assert commands_help_output =~ "--sort-by FIELD"

    statistics_help_output =
      capture_io(fn ->
        assert :ok = CLI.run(["help", "statistics"])
      end)

    assert statistics_help_output =~ "Usage: histlog statistics [options]"

    sessions_help_output =
      capture_io(fn ->
        assert :ok = CLI.run(["help", "sessions"])
      end)

    assert sessions_help_output =~ "Usage: histlog sessions [options]"

    for {command, expected} <- [
          {"consolidate", "Usage: histlog consolidate [options]"},
          {"import", "Usage: histlog import FILE [options]"},
          {"init", "Usage: histlog init [zsh|bash|fish]"},
          {"info", "Usage: histlog info [shell]"},
          {"doctor", "Usage: histlog doctor [zsh|bash|fish]"}
        ] do
      help_output =
        capture_io(fn ->
          assert :ok = CLI.run(["help", command])
        end)

      assert help_output =~ expected

      short_help_output =
        capture_io(fn ->
          assert :ok = CLI.run([command, "-h"])
        end)

      assert short_help_output == help_output
    end

    assert {:error, "no command-specific help for \"missing\""} = CLI.run(["help", "missing"])
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

  test "query skips malformed live rows with a warning", %{root: root, date: date} do
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

    File.write!(writer.live_path, "not-json\n", [:append])

    warning =
      capture_io(:stderr, fn ->
        output =
          capture_io(fn ->
            assert :ok =
                     CLI.run([
                       "query",
                       "--root",
                       root,
                       "--date",
                       Date.to_iso8601(date),
                       "--plain"
                     ])
          end)

        assert output == "mix test\n"
      end)

    assert warning =~ "skipped malformed record"
    assert warning =~ ".ndjson:"
  end

  test "paths command summarizes cwd and path-like arguments", %{root: root, date: date} do
    cwd = Path.join(root, "repo/app")
    parent = Path.dirname(cwd)
    relative_dir = Path.join(cwd, "lib")
    relative_file = Path.join(cwd, "mix.exs")
    absolute_file = Path.join(root, "tmp/file")

    File.mkdir_p!(relative_dir)
    File.mkdir_p!(Path.dirname(absolute_file))
    File.write!(relative_file, "")
    File.write!(absolute_file, "")

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
      SessionWriter.observe_execution(writer, "cat ./mix.exs #{absolute_file} missing", cwd, %{
        "timestamp" => "2026-05-06T20:00:00Z",
        "duration_ms" => 10,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, writer, _event} =
      SessionWriter.observe_execution(writer, "ls .. lib", cwd, %{
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
    assert %{"exec" => 2, "args" => 0, "path" => cwd} in rows
    assert %{"exec" => 0, "args" => 1, "path" => relative_file} in rows
    assert %{"exec" => 0, "args" => 1, "path" => absolute_file} in rows
    assert %{"exec" => 0, "args" => 1, "path" => parent} in rows
    assert %{"exec" => 0, "args" => 1, "path" => relative_dir} in rows
    refute Enum.any?(rows, &(&1["path"] == Path.join(cwd, "missing")))

    filtered_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "paths",
                   "mix",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--plain"
                 ])
      end)

    assert filtered_output == relative_file <> "\n"

    query_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "query",
                   "--path",
                   relative_dir,
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--plain"
                 ])
      end)

    assert query_output == "ls .. lib\n"
  end

  test "commands command summarizes command usage", %{root: root, date: date} do
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
        "duration_ms" => 10,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, writer, _event} =
      SessionWriter.observe_execution(writer, "git status", "/repo", %{
        "timestamp" => "2026-05-06T20:01:00Z",
        "duration_ms" => 20,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, writer, _event} =
      SessionWriter.observe_execution(writer, "mix test", "/repo/app", %{
        "timestamp" => "2026-05-06T20:02:00Z",
        "duration_ms" => 30,
        "exit_status" => 1,
        "completeness" => "complete"
      })

    {:ok, _writer, _event} = SessionWriter.close(writer, "2026-05-06T20:02:01Z")

    capture_io(fn ->
      assert :ok = CLI.run(["consolidate", "--root", root, "--date", Date.to_iso8601(date)])
    end)

    output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "commands",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--json"
                 ])
      end)

    rows = JSON.decode!(output)

    assert Enum.any?(
             rows,
             &match?(
               %{"command" => "mix test", "count" => 2, "successes" => 1, "failures" => 1},
               &1
             )
           )

    plain_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "commands",
                   "mix",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--plain"
                 ])
      end)

    assert plain_output == "mix test\n"

    table_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "commands",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--sort-by",
                   "count",
                   "--limit",
                   "1"
                 ])
      end)

    assert strip_ansi(table_output) =~ "Count Last Used"
    assert strip_ansi(table_output) =~ "mix test"
    refute strip_ansi(table_output) =~ "git status"

    assert {:error, error} = CLI.run(["commands", "[", "--regex"])
    assert error =~ "invalid regex"
  end

  test "statistics command reports high-level history counts", %{root: root, date: date} do
    cwd = Path.join(root, "repo")
    File.mkdir_p!(cwd)
    File.write!(Path.join(cwd, "mix.exs"), "")

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
      SessionWriter.observe_execution(writer, "mix test ./mix.exs", cwd, %{
        "timestamp" => "2026-05-06T20:00:00Z",
        "duration_ms" => 10,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, writer, _event} =
      SessionWriter.observe_execution(writer, "mix format", cwd, %{
        "timestamp" => "2026-05-06T20:01:00Z",
        "duration_ms" => 20,
        "exit_status" => 1,
        "completeness" => "complete"
      })

    {:ok, _writer, _event} = SessionWriter.close(writer, "2026-05-06T20:01:01Z")

    capture_io(fn ->
      assert :ok = CLI.run(["consolidate", "--root", root, "--date", Date.to_iso8601(date)])
    end)

    json =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "statistics",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--json"
                 ])
      end)

    assert %{
             "total_commands" => 2,
             "unique_commands" => 2,
             "sessions" => 1,
             "successful_commands" => 1,
             "failed_commands" => 1,
             "top_commands" => top_commands,
             "top_paths" => top_paths
           } = JSON.decode!(json)

    assert Enum.any?(top_commands, &(&1["command"] == "mix test ./mix.exs"))
    assert Enum.any?(top_paths, &(&1["path"] == Path.join(cwd, "mix.exs")))

    plain =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "statistics",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--plain"
                 ])
      end)

    assert plain =~ "total_commands=2"
    assert plain =~ "failed_commands=1"
  end

  test "sessions command lists recorded shell sessions with details", %{root: root, date: date} do
    {:ok, first} =
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

    {:ok, first, _event} =
      SessionWriter.observe_execution(first, "mix test", "/repo", %{
        "timestamp" => "2026-05-06T20:00:00Z",
        "duration_ms" => 1500,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, first, _event} =
      SessionWriter.observe_execution(first, "mix format", "/repo", %{
        "timestamp" => "2026-05-06T20:01:00Z",
        "duration_ms" => 10,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, _first, _event} = SessionWriter.close(first, "2026-05-06T20:01:01Z")

    {:ok, second} =
      SessionWriter.start(
        root: root,
        date: date,
        host: "machine",
        process_id: 1235,
        parent_process_id: 1200,
        shell: "fish",
        session_id: "session-2",
        monotonic_start: 12_346
      )

    {:ok, second, _event} =
      SessionWriter.observe_execution(second, "histlog paths", "/repo/app", %{
        "timestamp" => "2026-05-06T20:02:00Z",
        "duration_ms" => 100,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, _second, _event} = SessionWriter.close(second, "2026-05-06T20:02:01Z")

    capture_io(fn ->
      assert :ok = CLI.run(["consolidate", "--root", root, "--date", Date.to_iso8601(date)])
    end)

    output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "sessions",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--details"
                 ])
      end)

    stripped = strip_ansi(output)
    assert stripped =~ "Sess Start"
    assert stripped =~ "0001 #{local_display("2026-05-06T20:00:00Z")}"
    assert stripped =~ "0002 #{local_display("2026-05-06T20:02:00Z")}"
    assert stripped =~ "   2 zsh /repo"
    assert stripped =~ "Session 0001 sample commands:"
    assert stripped =~ "  mix test"

    json_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "sessions",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--limit",
                   "1",
                   "--json"
                 ])
      end)

    assert [%{"session" => "0002", "commands" => 1, "shell" => "fish"}] =
             JSON.decode!(json_output)
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

  test "query includes currently live session files", %{root: root, date: date} do
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
  end

  test "query warns when sqlite materialization cannot be read", %{root: root, date: date} do
    File.mkdir_p!(root)

    Database.with_connection(root, fn conn ->
      :ok = Schema.ensure(conn)

      Database.exec(
        conn,
        "UPDATE schema_metadata SET value = '999' WHERE key = 'schema_version'"
      )
    end)

    warning =
      capture_io(:stderr, fn ->
        output =
          capture_io(fn ->
            assert :ok =
                     CLI.run([
                       "query",
                       "--root",
                       root,
                       "--date",
                       Date.to_iso8601(date),
                       "--plain"
                     ])
          end)

        assert output == ""
      end)

    assert warning =~ "skipped sqlite materialization"
    assert warning =~ "schema_version_mismatch"
  end

  test "query family commands merge sqlite and live rows with materialized imports", %{
    root: root,
    date: date
  } do
    closed_cwd = Path.join(root, "closed")
    live_cwd = Path.join(root, "live")
    import_cwd = Path.join(root, "imported")
    File.mkdir_p!(closed_cwd)
    File.mkdir_p!(live_cwd)
    File.mkdir_p!(import_cwd)

    closed_file = Path.join(closed_cwd, "closed.txt")
    live_file = Path.join(live_cwd, "live.txt")
    import_file = Path.join(import_cwd, "import.txt")
    File.write!(closed_file, "")
    File.write!(live_file, "")
    File.write!(import_file, "")

    {:ok, closed} =
      SessionWriter.start(
        root: root,
        date: date,
        host: "machine",
        process_id: 1234,
        parent_process_id: 1200,
        shell: "zsh",
        session_id: "session-closed",
        monotonic_start: 12_345
      )

    {:ok, closed, _event} =
      SessionWriter.observe_execution(closed, "cat ./closed.txt", closed_cwd, %{
        "timestamp" => "2026-05-06T20:00:00Z",
        "duration_ms" => 10,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    {:ok, _closed, _event} = SessionWriter.close(closed, "2026-05-06T20:00:01Z")

    {:ok, live} =
      SessionWriter.start(
        root: root,
        date: date,
        host: "machine",
        process_id: 1235,
        parent_process_id: 1200,
        shell: "fish",
        session_id: "session-live",
        monotonic_start: 12_346
      )

    {:ok, _live, _event} =
      SessionWriter.observe_execution(live, "cat ./live.txt", live_cwd, %{
        "timestamp" => "2026-05-06T20:01:00Z",
        "duration_ms" => 20,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    import_source = Path.join(root, "import-source.ndjson")

    File.write!(
      import_source,
      JSON.encode!(%{
        "event" => "imported_execution",
        "command" => "cat #{import_file}",
        "cwd" => import_cwd,
        "timestamp" => "2026-05-06T20:02:00Z",
        "duration_ms" => 30,
        "exit_status" => 0
      }) <> "\n"
    )

    capture_io(fn ->
      assert :ok = CLI.run(["consolidate", "--root", root, "--date", Date.to_iso8601(date)])
    end)

    capture_io(fn ->
      assert :ok =
               CLI.run([
                 "import",
                 import_source,
                 "--root",
                 root,
                 "--date",
                 Date.to_iso8601(date),
                 "--source",
                 "native",
                 "--import-batch-id",
                 "native-batch"
               ])
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
                   "--plain"
                 ])
      end)

    assert query_output =~ "cat ./closed.txt\n"
    assert query_output =~ "cat ./live.txt\n"
    assert query_output =~ "cat #{import_file}\n"

    commands_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "commands",
                   "cat",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--plain"
                 ])
      end)

    assert commands_output =~ "cat ./closed.txt\n"
    assert commands_output =~ "cat ./live.txt\n"
    assert commands_output =~ "cat #{import_file}\n"

    paths_output =
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

    paths = JSON.decode!(paths_output)
    assert Enum.any?(paths, &(&1["path"] == closed_file))
    assert Enum.any?(paths, &(&1["path"] == live_file))
    assert Enum.any?(paths, &(&1["path"] == import_file))

    sessions_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "sessions",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--json"
                 ])
      end)

    sessions = JSON.decode!(sessions_output)
    assert Enum.any?(sessions, &(&1["session_id"] == "session-closed"))
    assert Enum.any?(sessions, &(&1["session_id"] == "session-live"))
    assert Enum.any?(sessions, &(&1["session"] == "(imported)"))

    export_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "export",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date)
                 ])
      end)

    assert export_output
           |> String.split("\n", trim: true)
           |> Enum.map(&JSON.decode!/1)
           |> Enum.map(& &1["command"])
           |> Enum.sort() == ["cat ./closed.txt", "cat ./live.txt", "cat #{import_file}"]
  end

  test "doctor reports database materialization integrity", %{root: root, date: date} do
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
    assert {:ok, _report} = Consolidator.consolidate(root: root, date: date)

    plain =
      capture_io(fn ->
        assert :ok = CLI.run(["doctor", "zsh", "--root", root, "--date", Date.to_iso8601(date)])
      end)

    plain = strip_ansi(plain)
    assert plain =~ "database: ok"
    assert plain =~ "schema: ok"
    assert plain =~ "materialization_counts: ok"
    assert plain =~ "sqlite_integrity: ok"
    assert plain =~ "orphan_checks: ok"

    output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "doctor",
                   "zsh",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--json"
                 ])
      end)

    assert %{
             "database_verification" => %{
               "ok" => true,
               "checks" => %{
                 "database" => %{"ok" => true},
                 "schema" => %{"ok" => true},
                 "counts" => %{"ok" => true}
               }
             },
             "database_maintenance" => %{
               "ok" => true,
               "checks" => %{
                 "integrity" => %{"ok" => true},
                 "orphans" => %{"ok" => true}
               }
             }
           } = JSON.decode!(output)

    Database.with_connection(root, fn conn ->
      Database.exec(conn, "DELETE FROM commands WHERE date = ?", [Date.to_iso8601(date)])
    end)

    output =
      capture_io(fn ->
        assert :ok = CLI.run(["doctor", "zsh", "--root", root, "--date", Date.to_iso8601(date)])
      end)

    output = strip_ansi(output)
    assert output =~ "diagnosis: attention"
    assert output =~ "materialization_counts: failed"
    assert output =~ "recommendation: run `histlog consolidate --rebuild --date YYYY-MM-DD`"

    output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "doctor",
                   "zsh",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--json"
                 ])
      end)

    assert %{
             "database_verification" => %{
               "ok" => false,
               "errors" => errors,
               "checks" => %{
                 "counts" => %{"ok" => false}
               }
             }
           } = JSON.decode!(output)

    assert Enum.any?(errors, &String.contains?(&1, "counts"))
  end

  test "verify command is migrated to doctor" do
    assert {:error, {:unknown_command, "verify"}} = CLI.run(["verify"])
    assert {:error, "no command-specific help for \"verify\""} = CLI.run(["help", "verify"])
  end

  test "verifier module still reports materialization integrity", %{root: root, date: date} do
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
    assert {:ok, _report} = Consolidator.consolidate(root: root, date: date)

    assert {:ok,
            %{
              "ok" => true,
              "checks" => %{
                "database" => %{"ok" => true},
                "schema" => %{"ok" => true},
                "counts" => %{"ok" => true}
              }
            }} = Histlog.Verifier.verify(root: root, date: date)

    Database.with_connection(root, fn conn ->
      Database.exec(conn, "DELETE FROM commands WHERE date = ?", [Date.to_iso8601(date)])
    end)

    assert {:error, %{"ok" => false, "errors" => errors}} =
             Histlog.Verifier.verify(root: root, date: date)

    assert Enum.any?(errors, &String.contains?(&1, "counts"))
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
    assert File.exists?(destination <> ".report.json")

    assert %{"records" => 3, "warnings" => []} =
             (destination <> ".report.json") |> File.read!() |> JSON.decode!()

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

    query_output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "query",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date),
                   "--plain"
                 ])
      end)

    assert query_output =~ "mix test\n"
    assert query_output =~ "git status\n"
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

    assert output =~ "HISTLOG_BIN=\"/opt/histlog/bin/histlog\""
    refute output =~ "HISTLOG_BIN:-/opt/histlog/bin/histlog"
  end

  test "init command rejects relative binary paths" do
    assert {:error, error} = CLI.run(["init", "zsh", "--binary", "histlog"])
    assert error =~ "absolute path"
  end

  test "init command accepts a default durability mode" do
    output =
      capture_io(fn ->
        assert :ok = CLI.run(["init", "zsh", "--durability", "fast"])
      end)

    assert output =~ "HISTLOG_DURABILITY=\"${HISTLOG_DURABILITY:-fast}\""
  end

  test "init and hook commands reject invalid durability modes" do
    assert {:error, error} = CLI.run(["init", "zsh", "--durability", "reckless"])
    assert error =~ "invalid durability"

    assert {:error, error} =
             CLI.run([
               "hook",
               "session-start",
               "--shell",
               "zsh",
               "--pid",
               "123",
               "--durability",
               "reckless"
             ])

    assert error =~ "invalid durability"
  end

  test "init command prints aliases only when requested" do
    output =
      capture_io(fn ->
        assert :ok = CLI.run(["init", "bash", "--aliases"])
      end)

    assert output =~ "histlog bash integration"
    assert output =~ "alias hl='histlog'"
  end

  test "doctor emits plain diagnostics by default", %{root: root, date: date} do
    File.mkdir_p!(root)
    Database.with_connection(root, fn conn -> Schema.ensure(conn) end)

    output =
      capture_io(fn ->
        assert :ok =
                 CLI.run(["doctor", "zsh", "--root", root, "--date", Date.to_iso8601(date)])
      end)

    output = strip_ansi(output)
    assert output =~ "detected_shell: zsh"
    assert output =~ "diagnosis: attention"
    assert output =~ "shell: ok"
    assert output =~ "database: ok"
    assert output =~ "schema: ok"
    assert output =~ "materialization_counts: ok"
    assert output =~ "sqlite_integrity: ok"
    assert output =~ "orphan_checks: ok"
  end

  test "info supports explicit plain and json output modes", %{root: root} do
    plain =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "info",
                   "zsh",
                   "--plain",
                   "--root",
                   root
                 ])
      end)

    plain = strip_ansi(plain)
    assert plain =~ "version:"
    assert plain =~ "data_root: #{root}"
    assert plain =~ "database: #{Path.join(root, "histlog.db")}"
    assert plain =~ "shell_argument: zsh"
    assert plain =~ "supported_shells: zsh, bash, fish"
    refute plain =~ "database: ok"
    refute plain =~ "schema:"
    refute plain =~ "diagnosis:"

    json =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "info",
                   "zsh",
                   "--json",
                   "--root",
                   root
                 ])
      end)

    assert %{
             "version" => _version,
             "paths" => %{"data_root" => ^root},
             "shell" => %{"argument" => "zsh", "supported" => ["zsh", "bash", "fish"]},
             "env" => env
           } = JSON.decode!(json)

    assert Map.has_key?(env, "HISTLOG_ROOT")

    assert {:error, "choose only one info output format"} =
             CLI.run(["info", "zsh", "--json", "--plain"])
  end

  test "doctor supports explicit json output mode", %{root: root, date: date} do
    output =
      capture_io(fn ->
        assert :ok =
                 CLI.run([
                   "doctor",
                   "zsh",
                   "--json",
                   "--root",
                   root,
                   "--date",
                   Date.to_iso8601(date)
                 ])
      end)

    assert %{"database_verification" => %{"ok" => false}} = JSON.decode!(output)

    assert {:error, "choose only one doctor output format"} =
             CLI.run(["doctor", "zsh", "--json", "--plain"])
  end

  test "command option parsing reports errors" do
    assert {:error, error} = CLI.run(["query", "--unknown"])
    assert error =~ "invalid options"

    assert {:error, error} = CLI.run(["query", "--date", "not-a-date"])
    assert error =~ "invalid date"

    assert {:error, error} = CLI.run(["query", "--regex", "["])
    assert error =~ "invalid regex"

    assert {:error, error} = CLI.run(["query", "--duration", "eventually"])
    assert error =~ "invalid duration"

    assert {:error, error} = CLI.run(["init", "zsh", "bash"])
    assert error =~ "unexpected arguments"
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
