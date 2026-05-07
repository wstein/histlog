defmodule Histlog.ImportTest do
  use ExUnit.Case, async: true

  alias Histlog.Import
  alias Histlog.Schema

  @fixtures Path.expand("../fixtures/import", __DIR__)

  test "builds synthetic import event streams" do
    events =
      Import.batch("import-session", "zsh_history", "batch-1", [
        %{
          "command" => "ls",
          "cwd" => "/tmp",
          "timestamp" => "2026-05-06T20:00:00Z",
          "exit_status" => nil
        }
      ])

    assert Enum.map(events, & &1["event"]) == [
             "import_batch_started",
             "imported_execution",
             "import_batch_finished"
           ]

    assert :ok = Schema.validate_sequence(events)
  end

  test "normalizes imported command text while preserving private marker" do
    assert [
             %{
               "event" => "imported_execution",
               "command" => "hidden imported",
               "is_private" => 1
             }
           ] =
             Import.batch("import-session", "zsh_history", "batch-1", [
               %{"command" => "  hidden imported  ", "timestamp" => "2026-05-06T16:00:00Z"}
             ])
             |> Enum.filter(&(&1["event"] == "imported_execution"))
  end

  test "parses zsh extended history fixtures" do
    content = File.read!(Path.join(@fixtures, "zsh_history"))

    assert {:ok,
            [
              %{"command" => "cd ~/work/histlog", "timestamp" => "2026-05-06T16:00:00Z"},
              %{"command" => "mix test", "timestamp" => "2026-05-06T16:01:00Z"},
              %{"command" => "git status", "timestamp" => nil}
            ]} = Import.parse("zsh_history", content)
  end

  test "parses bash history fixtures with timestamp markers" do
    content = File.read!(Path.join(@fixtures, "bash_history"))

    assert {:ok,
            [
              %{"command" => "cd ~/work/histlog", "timestamp" => "2026-05-06T16:00:00Z"},
              %{"command" => "mix test", "timestamp" => "2026-05-06T16:01:00Z"},
              %{"command" => "git status", "timestamp" => nil}
            ]} = Import.parse("bash_history", content)
  end

  test "parses fish history fixtures" do
    content = File.read!(Path.join(@fixtures, "fish_history"))

    assert {:ok,
            [
              %{
                "command" => "cd ~/work/histlog",
                "cwd" => "/Users/werner/github.com/wstein/histlog",
                "timestamp" => "2026-05-06T16:00:00Z"
              },
              %{"command" => "mix test", "timestamp" => "2026-05-06T16:01:00Z"},
              %{"command" => "git status", "timestamp" => nil}
            ]} = Import.parse("fish_history", content)
  end

  test "wraps parsed shell history in validated import batch events" do
    content = File.read!(Path.join(@fixtures, "zsh_history"))

    assert {:ok, events} = Import.from_source("import-session", "zsh_history", "batch-1", content)
    assert length(events) == 5

    assert [
             "import_batch_started",
             "imported_execution",
             "imported_execution",
             "imported_execution",
             "import_batch_finished"
           ] = Enum.map(events, & &1["event"])

    assert :ok = Schema.validate_sequence(events)
  end

  test "sanitizes invalid utf8 bytes before encoding import events" do
    content = <<": 1770000000:0;echo ", 131, " bad\n">>

    assert {:ok, events, report} =
             Import.from_source_with_report("import-session", "zsh_history", "batch-1", content)

    assert report["records"] == 1

    assert [%{"event" => "imported_execution", "command" => "echo ? bad"}] =
             Enum.filter(events, &(&1["event"] == "imported_execution"))

    assert JSON.encode!(events)
  end

  test "returns import diagnostics reports" do
    content = File.read!(Path.join(@fixtures, "zsh_history"))

    assert {:ok, events, report} =
             Import.from_source_with_report("import-session", "zsh_history", "batch-1", content)

    assert length(events) == 5
    assert report["records"] == 3
    assert report["warnings"] == []
    assert report["source"] == "zsh_history"
  end

  test "reports malformed native ndjson import rows without aborting" do
    content =
      "not-json\n" <>
        JSON.encode!(%{
          "schema_version" => 1,
          "event" => "imported_execution",
          "seq" => 1,
          "timestamp" => "2026-05-06T16:00:00Z",
          "command" => "mix test"
        }) <>
        "\n"

    assert {:ok, events, report} =
             Import.from_source_with_report("import-session", "ndjson", "batch-1", content)

    assert Enum.count(events, &(&1["event"] == "imported_execution")) == 1
    assert [%{"line" => 1, "reason" => reason}] = report["warnings"]
    assert reason =~ "invalid"
  end

  test "parses zsh multiline commands as one execution" do
    content = File.read!(Path.join(@fixtures, "zsh_multiline_history"))

    assert {:ok,
            [
              %{"command" => "printf 'one\ntwo'", "timestamp" => "2026-05-06T16:02:00Z"},
              %{"command" => "echo done", "timestamp" => "2026-05-06T16:03:00Z"}
            ]} = Import.parse("zsh_history", content)
  end

  test "parses bash multiline commands under timestamp markers" do
    content = File.read!(Path.join(@fixtures, "bash_multiline_history"))

    assert {:ok,
            [
              %{"command" => "printf 'one\ntwo'", "timestamp" => "2026-05-06T16:02:00Z"},
              %{"command" => "echo done", "timestamp" => "2026-05-06T16:03:00Z"}
            ]} = Import.parse("bash_history", content)
  end

  test "parses fish escaped scalar values" do
    content = File.read!(Path.join(@fixtures, "fish_escaped_history"))

    assert {:ok,
            [
              %{
                "command" => "printf \"one\ntwo\"",
                "cwd" => "/tmp/fish\\ path",
                "timestamp" => "2026-05-06T16:02:00Z"
              },
              %{
                "command" => "echo tab\tseparated",
                "timestamp" => "2026-05-06T16:03:00Z"
              }
            ]} = Import.parse("fish_history", content)
  end

  test "parses legacy histlog native ndjson export fixtures" do
    content = File.read!(Path.join(@fixtures, "legacy_histlog_export.ndjson"))

    assert {:ok,
            [
              %{
                "command" => "mix test",
                "cwd" => "/repo",
                "timestamp" => "2026-05-06T16:00:00Z",
                "exit_status" => 0
              }
            ]} = Import.parse("ndjson", content)
  end
end
