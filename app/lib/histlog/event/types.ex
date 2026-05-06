defmodule Histlog.Event.Types do
  @moduledoc """
  Internal typed event structs for canonical histlog event maps.

  The on-disk boundary remains compact JSON maps. These structs are an internal
  representation for code that benefits from explicit event shape.
  """

  defmodule SessionStarted do
    @moduledoc false
    defstruct [
      :schema_version,
      :event,
      :seq,
      :timestamp,
      :session_id,
      :process_id,
      :parent_process_id,
      :shell,
      :host,
      :tty,
      :monotonic_start
    ]
  end

  defmodule CommandDefined do
    @moduledoc false
    defstruct [:schema_version, :event, :seq, :timestamp, :command_id, :command, :redacted]
  end

  defmodule FolderDefined do
    @moduledoc false
    defstruct [:schema_version, :event, :seq, :timestamp, :folder_id, :folder]
  end

  defmodule ExecutionObserved do
    @moduledoc false
    defstruct [
      :schema_version,
      :event,
      :seq,
      :timestamp,
      :exec_id,
      :command_id,
      :cwd_id,
      :duration_ms,
      :exit_status,
      :completeness
    ]
  end

  defmodule SessionEnded do
    @moduledoc false
    defstruct [:schema_version, :event, :seq, :timestamp]
  end

  defmodule ImportedExecution do
    @moduledoc false
    defstruct [
      :schema_version,
      :event,
      :seq,
      :timestamp,
      :command,
      :cwd,
      :exit_status
    ]
  end

  def from_map(%{"event" => "session_started"} = event), do: typed(event, SessionStarted)
  def from_map(%{"event" => "command_defined"} = event), do: typed(event, CommandDefined)
  def from_map(%{"event" => "folder_defined"} = event), do: typed(event, FolderDefined)
  def from_map(%{"event" => "execution_observed"} = event), do: typed(event, ExecutionObserved)
  def from_map(%{"event" => "session_ended"} = event), do: typed(event, SessionEnded)
  def from_map(%{"event" => "imported_execution"} = event), do: typed(event, ImportedExecution)
  def from_map(%{"event" => event}), do: {:error, {:unsupported_typed_event, event}}
  def from_map(_event), do: {:error, :event_must_be_map}

  def to_map(%module{} = typed)
      when module in [
             SessionStarted,
             CommandDefined,
             FolderDefined,
             ExecutionObserved,
             SessionEnded,
             ImportedExecution
           ] do
    typed
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, Atom.to_string(key), value)
    end)
  end

  defp typed(event, module) do
    fields = module.__struct__() |> Map.from_struct() |> Map.keys()

    typed =
      fields
      |> Map.new(fn field -> {field, Map.get(event, Atom.to_string(field))} end)
      |> then(&struct(module, &1))

    {:ok, typed}
  end
end
