defmodule Histlog.EventTest do
  use ExUnit.Case, async: true

  alias Histlog.Event
  alias Histlog.NDJSON
  alias Histlog.Schema

  test "builds and validates an observed execution event" do
    assert {:ok, event} =
             Event.new("execution_observed", "session-1", 1, %{
               "exec_id" => 7,
               "command_id" => 1,
               "cwd_id" => 2,
               "started_at" => "2026-05-06T20:00:00Z",
               "ended_at" => nil,
               "duration_ms" => nil,
               "exit_status" => nil,
               "completeness" => "partial"
             })

    assert event["schema_version"] == 1
    assert event["event"] == "execution_observed"
    assert event["seq"] == 1
    assert :ok = Schema.validate_event(event)
  end

  test "encodes and decodes NDJSON lines" do
    event =
      Event.new!("command_defined", "session-1", 1, %{
        "command_id" => 1,
        "command" => "ls -alh"
      })

    assert {:ok, [decoded]} = event |> List.wrap() |> NDJSON.encode!() |> NDJSON.decode()
    assert decoded == event
  end

  test "redacts common secret-looking command values before persistence" do
    event =
      Event.new!("command_defined", "session-1", 1, %{
        "command_id" => 1,
        "command" => "deploy token=super-secret-token-value"
      })

    assert event["redacted"] == true
    assert event["command"] == "deploy token=[REDACTED]"
  end

  test "rejects invalid event types" do
    assert {:error, {:unknown_event, "made_up"}} = Event.new("made_up", "session-1", 1)
  end

  test "validates strict gapless session sequence numbers" do
    events = [
      Event.new!("session_ended", "session-1", 1, %{"ended_at" => "2026-05-06T20:00:00Z"}),
      Event.new!("session_ended", "session-1", 3, %{"ended_at" => "2026-05-06T20:00:01Z"})
    ]

    assert {:error, {:invalid_sequence, [1, 3]}} = Schema.validate_sequence(events)
  end
end
