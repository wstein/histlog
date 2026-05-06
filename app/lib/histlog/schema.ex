defmodule Histlog.Schema do
  @moduledoc """
  Validation for histlog canonical event maps and session sequences.
  """

  @schema_version Histlog.schema_version()

  @event_fields %{
    "session_started" => ["session_id", "process_id", "parent_process_id", "shell", "host"],
    "session_ended" => [],
    "session_aborted" => ["reason"],
    "command_defined" => ["command_id", "command"],
    "folder_defined" => ["folder_id", "folder"],
    "execution_observed" => ["exec_id", "command_id", "cwd_id", "completeness"],
    "execution_finished" => ["exec_id", "completeness"],
    "cwd_changed" => ["new_cwd_id"],
    "import_batch_started" => ["source", "import_batch_id"],
    "imported_execution" => ["command", "timestamp"],
    "import_batch_finished" => ["import_batch_id", "records"]
  }

  @doc """
  Validates a single event map.
  """
  def validate_event(event) when is_map(event) do
    with :ok <- require_field(event, "schema_version"),
         :ok <- equal(event, "schema_version", @schema_version),
         :ok <- require_string(event, "event"),
         :ok <- require_positive_integer(event, "seq"),
         :ok <- require_field(event, "timestamp"),
         :ok <- validate_type_fields(event) do
      :ok
    end
  end

  def validate_event(_event), do: {:error, :event_must_be_map}

  @doc """
  Raises when an event is invalid.
  """
  def validate_event!(event) do
    case validate_event(event) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "invalid histlog event: #{inspect(reason)}"
    end
  end

  @doc """
  Validates that session events have strictly increasing sequence numbers with no gaps.
  """
  def validate_sequence(events) when is_list(events) do
    events
    |> Enum.map(&Map.get(&1, "seq"))
    |> validate_sequence_numbers()
  end

  defp validate_sequence_numbers(seq_numbers) do
    expected = Enum.to_list(1..length(seq_numbers)//1)

    if seq_numbers == expected do
      :ok
    else
      {:error, {:invalid_sequence, seq_numbers}}
    end
  end

  defp validate_type_fields(%{"event" => event_type} = event) do
    case Map.fetch(@event_fields, event_type) do
      {:ok, required_fields} ->
        Enum.reduce_while(required_fields, :ok, fn field, :ok ->
          case require_field(event, field) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      :error ->
        {:error, {:unknown_event, event_type}}
    end
  end

  defp require_field(event, field) do
    if Map.has_key?(event, field) do
      :ok
    else
      {:error, {:missing_field, field}}
    end
  end

  defp equal(event, field, expected) do
    if Map.get(event, field) == expected do
      :ok
    else
      {:error, {:invalid_field, field}}
    end
  end

  defp require_string(event, field) do
    with :ok <- require_field(event, field) do
      if is_binary(Map.fetch!(event, field)) and Map.fetch!(event, field) != "" do
        :ok
      else
        {:error, {:invalid_field, field}}
      end
    end
  end

  defp require_positive_integer(event, field) do
    with :ok <- require_field(event, field) do
      value = Map.fetch!(event, field)

      if is_integer(value) and value > 0 do
        :ok
      else
        {:error, {:invalid_field, field}}
      end
    end
  end
end
