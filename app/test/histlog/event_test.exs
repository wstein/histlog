defmodule Histlog.EventTest do
  use ExUnit.Case, async: true

  alias Histlog.Event
  alias Histlog.NDJSON
  alias Histlog.Schema

  test "builds and validates an observed execution event" do
    assert {:ok, event} =
             Event.new("execution_observed", 1, %{
               "exec_id" => 7,
               "command_id" => 1,
               "cwd_id" => 2,
               "timestamp" => "2026-05-06T20:00:00Z",
               "duration_ms" => nil,
               "exit_status" => nil,
               "completeness" => "partial"
             })

    assert event["schema_version"] == 1
    assert event["event"] == "execution_observed"
    assert event["seq"] == 1
    assert event["timestamp"] == "2026-05-06T20:00:00Z"
    refute Map.has_key?(event, "session_id")
    refute Map.has_key?(event, "recorded_at")
    refute Map.has_key?(event, "started_at")
    refute Map.has_key?(event, "ended_at")
    assert :ok = Schema.validate_event(event)
  end

  test "encodes and decodes NDJSON lines" do
    event =
      Event.new!("command_defined", 1, %{
        "command_id" => 1,
        "command" => "ls -alh"
      })

    assert {:ok, [decoded]} = event |> List.wrap() |> NDJSON.encode!() |> NDJSON.decode()
    assert decoded == event
  end

  test "converts canonical maps to typed internal events and back" do
    event =
      Event.new!("execution_observed", 1, %{
        "exec_id" => 7,
        "command_id" => 1,
        "cwd_id" => 2,
        "timestamp" => "2026-05-06T20:00:00Z",
        "duration_ms" => 42,
        "exit_status" => 0,
        "completeness" => "complete"
      })

    assert {:ok, typed} = Event.to_typed(event)
    assert %Histlog.Event.Types.ExecutionObserved{exec_id: 7, completeness: "complete"} = typed
    assert Event.from_typed(typed) == event
  end

  test "redacts common secret-looking command values before persistence" do
    event =
      Event.new!("command_defined", 1, %{
        "command_id" => 1,
        "command" => "deploy token=super-secret-token-value"
      })

    assert event["redacted"] == true
    assert event["command"] == "deploy token=[REDACTED]"
  end

  test "redacts separated and quoted secret command values" do
    cases = [
      {"export TOKEN \"super-secret-token-value\"", "export TOKEN \"[REDACTED]\""},
      {"API_KEY='super-secret-token-value' mix test", "API_KEY='[REDACTED]' mix test"},
      {"printf 'password: super-secret-token-value'", "printf 'password: [REDACTED]'"},
      {"aws configure set aws_secret_access_key abcdefghijklmnopqrstuvwxyz123456",
       "aws configure set aws_secret_access_key [REDACTED]"}
    ]

    for {command, redacted} <- cases do
      event =
        Event.new!("command_defined", 1, %{
          "command_id" => 1,
          "command" => command
        })

      assert event["redacted"] == true
      assert event["command"] == redacted
    end
  end

  test "rejects invalid event types" do
    assert {:error, {:unknown_event, "made_up"}} = Event.new("made_up", 1)
  end

  test "validates strict gapless session sequence numbers" do
    events = [
      Event.new!("session_ended", 1, %{"timestamp" => "2026-05-06T20:00:00Z"}),
      Event.new!("session_ended", 3, %{"timestamp" => "2026-05-06T20:00:01Z"})
    ]

    assert {:error, {:invalid_sequence, [1, 3]}} = Schema.validate_sequence(events)
  end

  test "rejects invalid observed execution semantics" do
    assert {:error, {:invalid_field, "completeness"}} =
             Event.new("execution_observed", 1, %{
               "exec_id" => 1,
               "command_id" => 1,
               "cwd_id" => 1,
               "duration_ms" => 0,
               "exit_status" => 0,
               "completeness" => "maybe"
             })

    assert {:error, {:invalid_field, "duration_ms"}} =
             Event.new("execution_observed", 1, %{
               "exec_id" => 1,
               "command_id" => 1,
               "cwd_id" => 1,
               "duration_ms" => -1,
               "exit_status" => 0,
               "completeness" => "complete"
             })
  end

  test "rejects invalid timestamps" do
    event =
      Event.new!("session_ended", 1, %{
        "timestamp" => "2026-05-06T20:00:00Z"
      })

    assert {:error, {:invalid_field, "timestamp"}} =
             Schema.validate_event(%{event | "timestamp" => "not-a-time"})
  end

  test "validates catalog references across a complete session stream" do
    events = [
      Event.new!("session_started", 1, %{
        "session_id" => "session-1",
        "process_id" => 1234,
        "parent_process_id" => 1200,
        "shell" => "zsh",
        "host" => "machine",
        "timestamp" => "2026-05-06T20:00:00Z"
      }),
      Event.new!("command_defined", 2, %{"command_id" => 1, "command" => "pwd"}),
      Event.new!("folder_defined", 3, %{"folder_id" => 1, "folder" => "/repo"}),
      Event.new!("execution_observed", 4, %{
        "exec_id" => 1,
        "command_id" => 1,
        "cwd_id" => 1,
        "completeness" => "complete"
      }),
      Event.new!("session_ended", 5, %{"timestamp" => "2026-05-06T20:00:01Z"})
    ]

    assert :ok = Schema.validate_session(events)

    broken = List.update_at(events, 3, &Map.put(&1, "command_id", 2))
    assert {:error, {:undefined_command_id, 2}} = Schema.validate_session(broken)
  end

  test "rejects repeated session ids outside the session header" do
    events = [
      Event.new!("session_started", 1, %{
        "session_id" => "session-1",
        "process_id" => 1234,
        "parent_process_id" => 1200,
        "shell" => "zsh",
        "host" => "machine",
        "timestamp" => "2026-05-06T20:00:00Z"
      }),
      Event.new!("session_ended", 2, %{"timestamp" => "2026-05-06T20:00:01Z"})
      |> Map.put("session_id", "session-1")
    ]

    assert {:error, {:unexpected_session_id, 2}} = Schema.validate_session(events)
  end
end
