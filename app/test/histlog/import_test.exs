defmodule Histlog.ImportTest do
  use ExUnit.Case, async: true

  alias Histlog.Import
  alias Histlog.Schema

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
end
