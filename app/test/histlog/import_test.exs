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
end
