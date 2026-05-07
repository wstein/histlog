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
         :ok <- require_timestamp(event, "timestamp"),
         :ok <- validate_type_fields(event),
         :ok <- validate_semantics(event) do
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

  @doc """
  Validates a complete canonical session event stream.
  """
  def validate_session(events) when is_list(events) do
    with :ok <- validate_non_empty_session(events),
         :ok <- validate_sequence(events),
         :ok <- validate_each_event(events),
         :ok <- validate_session_header(events) do
      validate_catalog_references(events)
    end
  end

  def validate_session(_events), do: {:error, :session_must_be_list}

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

  defp validate_semantics(%{"event" => "session_started"} = event) do
    with :ok <- require_string(event, "session_id"),
         :ok <- require_positive_integer(event, "process_id"),
         :ok <- require_non_negative_integer(event, "parent_process_id"),
         :ok <- require_string(event, "shell"),
         :ok <- require_string(event, "host") do
      :ok
    end
  end

  defp validate_semantics(%{"event" => "session_aborted"} = event) do
    allowed_value(event, "reason", ["timeout", "crash", "unknown"])
  end

  defp validate_semantics(%{"event" => "command_defined"} = event) do
    with :ok <- require_positive_integer(event, "command_id"),
         :ok <- optional_boolean_integer(event, "is_private") do
      require_string(event, "command")
    end
  end

  defp validate_semantics(%{"event" => "folder_defined"} = event) do
    with :ok <- require_positive_integer(event, "folder_id") do
      require_string(event, "folder")
    end
  end

  defp validate_semantics(%{"event" => "execution_observed"} = event) do
    with :ok <- require_positive_integer(event, "exec_id"),
         :ok <- require_positive_integer(event, "command_id"),
         :ok <- require_positive_integer(event, "cwd_id"),
         :ok <- optional_non_negative_integer(event, "duration_ms"),
         :ok <- optional_integer(event, "exit_status") do
      allowed_value(event, "completeness", ["complete", "partial"])
    end
  end

  defp validate_semantics(%{"event" => "execution_finished"} = event) do
    with :ok <- require_positive_integer(event, "exec_id"),
         :ok <- optional_non_negative_integer(event, "duration_ms"),
         :ok <- optional_integer(event, "exit_status") do
      allowed_value(event, "completeness", ["complete", "partial"])
    end
  end

  defp validate_semantics(%{"event" => "cwd_changed"} = event) do
    require_positive_integer(event, "new_cwd_id")
  end

  defp validate_semantics(%{"event" => "import_batch_started"} = event) do
    with :ok <- optional_string(event, "session_id"),
         :ok <- require_string(event, "source") do
      require_string(event, "import_batch_id")
    end
  end

  defp validate_semantics(%{"event" => "imported_execution"} = event) do
    with :ok <- require_string(event, "command"),
         :ok <- optional_string(event, "cwd") do
      optional_integer(event, "exit_status")
    end
  end

  defp validate_semantics(%{"event" => "import_batch_finished"} = event) do
    with :ok <- require_string(event, "import_batch_id") do
      require_non_negative_integer(event, "records")
    end
  end

  defp validate_semantics(_event), do: :ok

  defp validate_non_empty_session([]), do: {:error, :empty_session}
  defp validate_non_empty_session(_events), do: :ok

  defp validate_each_event(events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      case validate_event(event) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_session_header([
         %{"event" => "session_started", "session_id" => session_id} | events
       ])
       when is_binary(session_id) and session_id != "" do
    validate_session_id_boundary(events)
  end

  defp validate_session_header(_events), do: {:error, :missing_session_header}

  defp validate_session_id_boundary(events) do
    case Enum.find(events, &Map.has_key?(&1, "session_id")) do
      nil -> :ok
      event -> {:error, {:unexpected_session_id, Map.get(event, "seq")}}
    end
  end

  defp validate_catalog_references(events) do
    events
    |> Enum.reduce_while({MapSet.new(), MapSet.new(), MapSet.new()}, fn event,
                                                                        {commands, folders, execs} ->
      case validate_catalog_event(event, commands, folders, execs) do
        {:ok, next_state} -> {:cont, next_state}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {_commands, _folders, _execs} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_catalog_event(
         %{"event" => "command_defined", "command_id" => id},
         commands,
         folders,
         execs
       ) do
    if MapSet.member?(commands, id) do
      {:error, {:duplicate_command_id, id}}
    else
      {:ok, {MapSet.put(commands, id), folders, execs}}
    end
  end

  defp validate_catalog_event(
         %{"event" => "folder_defined", "folder_id" => id},
         commands,
         folders,
         execs
       ) do
    if MapSet.member?(folders, id) do
      {:error, {:duplicate_folder_id, id}}
    else
      {:ok, {commands, MapSet.put(folders, id), execs}}
    end
  end

  defp validate_catalog_event(
         %{
           "event" => "execution_observed",
           "exec_id" => exec_id,
           "command_id" => command_id,
           "cwd_id" => cwd_id
         },
         commands,
         folders,
         execs
       ) do
    cond do
      MapSet.member?(execs, exec_id) ->
        {:error, {:duplicate_exec_id, exec_id}}

      !MapSet.member?(commands, command_id) ->
        {:error, {:undefined_command_id, command_id}}

      !MapSet.member?(folders, cwd_id) ->
        {:error, {:undefined_folder_id, cwd_id}}

      true ->
        {:ok, {commands, folders, MapSet.put(execs, exec_id)}}
    end
  end

  defp validate_catalog_event(
         %{"event" => "cwd_changed", "new_cwd_id" => folder_id},
         commands,
         folders,
         execs
       ) do
    if MapSet.member?(folders, folder_id) do
      {:ok, {commands, folders, execs}}
    else
      {:error, {:undefined_folder_id, folder_id}}
    end
  end

  defp validate_catalog_event(_event, commands, folders, execs),
    do: {:ok, {commands, folders, execs}}

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

  defp optional_string(event, field) do
    if Map.has_key?(event, field) and !is_nil(Map.get(event, field)) do
      require_string(event, field)
    else
      :ok
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

  defp require_non_negative_integer(event, field) do
    with :ok <- require_field(event, field) do
      value = Map.fetch!(event, field)

      if is_integer(value) and value >= 0 do
        :ok
      else
        {:error, {:invalid_field, field}}
      end
    end
  end

  defp optional_non_negative_integer(event, field) do
    if Map.has_key?(event, field) and !is_nil(Map.get(event, field)) do
      require_non_negative_integer(event, field)
    else
      :ok
    end
  end

  defp optional_boolean_integer(event, field) do
    case Map.fetch(event, field) do
      :error -> :ok
      {:ok, value} when value in [0, 1, true, false] -> :ok
      {:ok, value} -> {:error, {:invalid_boolean_integer, field, value}}
    end
  end

  defp optional_integer(event, field) do
    if Map.has_key?(event, field) and !is_nil(Map.get(event, field)) do
      value = Map.get(event, field)

      if is_integer(value) do
        :ok
      else
        {:error, {:invalid_field, field}}
      end
    else
      :ok
    end
  end

  defp require_timestamp(event, field) do
    with :ok <- require_string(event, field) do
      case DateTime.from_iso8601(Map.fetch!(event, field)) do
        {:ok, _datetime, _offset} -> :ok
        {:error, _reason} -> {:error, {:invalid_field, field}}
      end
    end
  end

  defp allowed_value(event, field, allowed_values) do
    value = Map.get(event, field)

    if value in allowed_values do
      :ok
    else
      {:error, {:invalid_field, field}}
    end
  end
end
