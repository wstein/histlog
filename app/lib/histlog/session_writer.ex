defmodule Histlog.SessionWriter do
  @moduledoc """
  Append-only writer for one shell session.
  """

  alias Histlog.Event
  alias Histlog.Storage

  defstruct [
    :root,
    :date,
    :session_id,
    :host,
    :process_id,
    :parent_process_id,
    :shell,
    :started_at,
    :monotonic_start,
    :live_path,
    :closed_path,
    :durability,
    seq: 0,
    next_command_id: 1,
    next_folder_id: 1,
    next_exec_id: 1,
    commands: %{},
    folders: %{}
  ]

  @doc """
  Rebuilds a writer from persisted hook state.
  """
  def from_state(state) when is_map(state) do
    %__MODULE__{
      root: state["root"],
      date: Date.from_iso8601!(state["date"]),
      session_id: state["session_id"],
      host: state["host"],
      process_id: state["process_id"],
      parent_process_id: state["parent_process_id"],
      shell: state["shell"],
      started_at: state["started_at"],
      monotonic_start: state["monotonic_start"],
      live_path: state["live_path"],
      closed_path: state["closed_path"],
      durability: Histlog.Durability.normalize!(state["durability"]),
      seq: state["seq"],
      next_command_id: state["next_command_id"],
      next_folder_id: state["next_folder_id"],
      next_exec_id: state["next_exec_id"],
      commands: state["commands"] || %{},
      folders: state["folders"] || %{}
    }
  end

  @doc """
  Converts a writer to JSON-serializable hook state.
  """
  def to_state(%__MODULE__{} = writer) do
    %{
      "root" => writer.root,
      "date" => Date.to_iso8601(writer.date),
      "session_id" => writer.session_id,
      "host" => writer.host,
      "process_id" => normalize_process_id(writer.process_id),
      "parent_process_id" => normalize_process_id(writer.parent_process_id),
      "shell" => writer.shell,
      "started_at" => writer.started_at,
      "monotonic_start" => writer.monotonic_start,
      "live_path" => writer.live_path,
      "closed_path" => writer.closed_path,
      "durability" => writer.durability,
      "seq" => writer.seq,
      "next_command_id" => writer.next_command_id,
      "next_folder_id" => writer.next_folder_id,
      "next_exec_id" => writer.next_exec_id,
      "commands" => writer.commands,
      "folders" => writer.folders
    }
  end

  @doc """
  Starts a session file and writes `session_started`.
  """
  def start(opts \\ []) do
    root = Storage.root(opts)
    date = Keyword.get(opts, :date, Date.utc_today())
    host = Keyword.get_lazy(opts, :host, &default_host/0)
    process_id = Keyword.get(opts, :process_id, System.pid())
    parent_process_id = Keyword.get(opts, :parent_process_id, 0)
    shell = Keyword.get(opts, :shell, "unknown")
    started_at = Keyword.get_lazy(opts, :started_at, &now/0)
    monotonic_start = Keyword.get_lazy(opts, :monotonic_start, &System.monotonic_time/0)
    start_ns = System.convert_time_unit(monotonic_start, :native, :nanosecond)
    session_id = Keyword.get_lazy(opts, :session_id, &new_session_id/0)
    durability = Histlog.Durability.normalize!(Keyword.get(opts, :durability, "balanced"))
    filename = Storage.session_filename(host, process_id, start_ns)

    Storage.ensure_layout(root, date)

    writer = %__MODULE__{
      root: root,
      date: date,
      session_id: session_id,
      host: host,
      process_id: process_id,
      parent_process_id: parent_process_id,
      shell: shell,
      started_at: started_at,
      monotonic_start: monotonic_start,
      live_path: Path.join(Storage.live_dir(root, date), filename),
      closed_path: Path.join(Storage.closed_dir(root, date), filename),
      durability: durability
    }

    attrs = %{
      "session_id" => session_id,
      "process_id" => normalize_process_id(process_id),
      "parent_process_id" => normalize_process_id(parent_process_id),
      "shell" => shell,
      "host" => host,
      "timestamp" => started_at,
      "monotonic_start" => monotonic_start
    }

    with {:ok, writer, _event} <- append(writer, "session_started", attrs) do
      {:ok, writer}
    end
  end

  @doc """
  Defines a command once per session and returns its session-local id.
  """
  def define_command(%__MODULE__{} = writer, command) when is_binary(command) do
    case Map.fetch(writer.commands, command) do
      {:ok, command_id} ->
        {:ok, writer, command_id}

      :error ->
        command_id = writer.next_command_id

        attrs = %{
          "command_id" => command_id,
          "command" => command
        }

        with {:ok, writer, _event} <- append(writer, "command_defined", attrs) do
          writer = %{
            writer
            | commands: Map.put(writer.commands, command, command_id),
              next_command_id: command_id + 1
          }

          {:ok, writer, command_id}
        end
    end
  end

  @doc """
  Defines a folder once per session and returns its session-local id.
  """
  def define_folder(%__MODULE__{} = writer, folder) when is_binary(folder) do
    case Map.fetch(writer.folders, folder) do
      {:ok, folder_id} ->
        {:ok, writer, folder_id}

      :error ->
        folder_id = writer.next_folder_id

        attrs = %{
          "folder_id" => folder_id,
          "folder" => folder
        }

        with {:ok, writer, _event} <- append(writer, "folder_defined", attrs) do
          writer = %{
            writer
            | folders: Map.put(writer.folders, folder, folder_id),
              next_folder_id: folder_id + 1
          }

          {:ok, writer, folder_id}
        end
    end
  end

  @doc """
  Records an observed execution, defining command and cwd catalog entries if needed.
  """
  def observe_execution(%__MODULE__{} = writer, command, cwd, attrs \\ %{}) do
    with {:ok, writer, command_id} <- define_command(writer, command),
         {:ok, writer, cwd_id} <- define_folder(writer, cwd) do
      exec_id = writer.next_exec_id

      event_attrs =
        Map.merge(
          %{
            "exec_id" => exec_id,
            "command_id" => command_id,
            "cwd_id" => cwd_id,
            "timestamp" => Map.get(attrs, "timestamp", Map.get(attrs, "started_at", now())),
            "duration_ms" => Map.get(attrs, "duration_ms"),
            "exit_status" => Map.get(attrs, "exit_status"),
            "completeness" => Map.get(attrs, "completeness", "partial")
          },
          Map.drop(attrs, [
            "timestamp",
            "started_at",
            "ended_at",
            "duration_ms",
            "exit_status",
            "completeness"
          ])
        )

      with {:ok, writer, event} <- append(writer, "execution_observed", event_attrs) do
        {:ok, %{writer | next_exec_id: exec_id + 1}, event}
      end
    end
  end

  @doc """
  Writes `session_ended` and atomically moves the session to `closed/`.
  """
  def close(%__MODULE__{} = writer, ended_at \\ now()) do
    with {:ok, writer, event} <- append(writer, "session_ended", %{"timestamp" => ended_at}),
         :ok <- Storage.close_session(writer.live_path, writer.closed_path) do
      {:ok, writer, event}
    end
  end

  defp append(%__MODULE__{} = writer, event_type, attrs) do
    seq = writer.seq + 1

    with {:ok, event} <- Event.new(event_type, seq, attrs),
         :ok <-
           Storage.append_event(writer.live_path, event,
             sync?: sync_event?(writer.durability, event_type)
           ) do
      {:ok, %{writer | seq: seq}, event}
    end
  end

  defp sync_event?("safe", _event_type), do: true

  defp sync_event?("balanced", event_type),
    do: event_type in ["session_started", "session_ended", "session_aborted"]

  defp sync_event?("fast", _event_type), do: false

  defp default_host do
    case :inet.gethostname() do
      {:ok, host} -> List.to_string(host)
      {:error, _reason} -> "unknown"
    end
  end

  defp new_session_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp now do
    DateTime.utc_now()
    |> DateTime.truncate(:microsecond)
    |> DateTime.to_iso8601()
  end

  defp normalize_process_id(pid) when is_integer(pid), do: pid

  defp normalize_process_id(pid) when is_binary(pid) do
    case Integer.parse(pid) do
      {integer, ""} -> integer
      _other -> 0
    end
  end
end
