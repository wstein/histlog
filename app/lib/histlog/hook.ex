defmodule Histlog.Hook do
  @moduledoc """
  Trusted CLI boundary called by generated shell adapters.
  """

  alias Histlog.SessionWriter
  alias Histlog.Storage

  @doc """
  Starts a session and persists hook state for later hook invocations.
  """
  def session_start(opts) do
    root = Storage.root(opts)

    with {:ok, durability} <- Histlog.Durability.normalize(Keyword.get(opts, :durability)),
         {:ok, writer} <-
           opts
           |> Keyword.put(:durability, durability)
           |> session_start_writer_opts(root)
           |> SessionWriter.start(),
         :ok <- write_state(writer) do
      {:ok, writer.session_id}
    end
  end

  @doc """
  Records command start evidence.
  """
  def preexec(opts) do
    with {:ok, writer} <- load_writer(opts),
         pending = %{
           "command" => Keyword.fetch!(opts, :command),
           "cwd" => Keyword.fetch!(opts, :cwd),
           "started_at" => Keyword.fetch!(opts, :started_at)
         },
         :ok <- write_state(writer, pending) do
      :ok
    end
  end

  @doc """
  Records an observed execution using pending preexec state when available.
  """
  def precmd(opts) do
    with {:ok, writer, pending} <- load_writer_with_pending(opts) do
      attrs = %{
        "timestamp" => timestamp(Map.get(pending, "started_at", Keyword.get(opts, :ended_at))),
        "ended_at" => Keyword.get(opts, :ended_at),
        "duration_ms" =>
          duration_ms(Map.get(pending, "started_at"), Keyword.get(opts, :ended_at)),
        "exit_status" => Keyword.get(opts, :exit_status),
        "completeness" => completeness(pending, opts)
      }

      with {:ok, writer, _event} <-
             SessionWriter.observe_execution(
               writer,
               Map.get(pending, "command", ""),
               Keyword.get(opts, :cwd, Map.get(pending, "cwd", "")),
               attrs
             ),
           :ok <- write_state(writer, nil) do
        :ok
      end
    end
  end

  @doc """
  Ends a session and removes hook state.
  """
  def session_end(opts) do
    with {:ok, writer, _pending} <- load_writer_with_pending(opts),
         {:ok, _writer, _event} <-
           SessionWriter.close(writer, Keyword.get(opts, :ended_at, now())),
         :ok <- remove_state(Storage.root(opts), Keyword.fetch!(opts, :session)) do
      :ok
    end
  end

  @doc """
  Returns the hook state path for a session id.
  """
  def state_path(root, session_id) do
    safe_session_id = String.replace(session_id, ~r/[^A-Za-z0-9_.=-]/, "_")
    Path.join(Storage.hook_state_dir(root), safe_session_id <> ".json")
  end

  defp load_writer(opts) do
    with {:ok, writer, _pending} <- load_writer_with_pending(opts) do
      {:ok, writer}
    end
  end

  defp session_start_writer_opts(opts, root) do
    [
      root: root,
      shell: Keyword.fetch!(opts, :shell),
      process_id: Keyword.fetch!(opts, :pid),
      parent_process_id: Keyword.get(opts, :ppid, 0),
      started_at: Keyword.get(opts, :started_at),
      host: Keyword.get(opts, :host, default_host()),
      session_id: Keyword.get(opts, :session_id),
      durability: Keyword.get(opts, :durability),
      date: Keyword.get(opts, :date, Date.utc_today())
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp load_writer_with_pending(opts) do
    root = Storage.root(opts)
    session_id = Keyword.fetch!(opts, :session)

    with {:ok, content} <- File.read(state_path(root, session_id)),
         {:ok, state} <- decode_hook_state(content),
         {:ok, writer} <- writer_from_state(state) do
      {:ok, writer, state["pending"]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_hook_state(content) do
    case JSON.decode(content) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:error, {:invalid_hook_state, format_decode_error(reason)}}
    end
  end

  defp format_decode_error(reason) when is_binary(reason), do: reason

  defp format_decode_error(reason) do
    if is_exception(reason) do
      Exception.message(reason)
    else
      inspect(reason)
    end
  end

  defp writer_from_state(%{"writer" => writer_state}) when is_map(writer_state) do
    {:ok, SessionWriter.from_state(writer_state)}
  rescue
    exception in [ArgumentError, FunctionClauseError, KeyError] ->
      {:error, {:invalid_hook_state, Exception.message(exception)}}
  end

  defp writer_from_state(_state), do: {:error, {:invalid_hook_state, "missing writer state"}}

  defp write_state(writer, pending \\ nil) do
    state = %{
      "writer" => SessionWriter.to_state(writer),
      "pending" => pending
    }

    Storage.atomic_write(state_path(writer.root, writer.session_id), JSON.encode!(state) <> "\n")
  end

  defp remove_state(root, session_id) do
    case File.rm(state_path(root, session_id)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp duration_ms(nil, _ended_at), do: nil
  defp duration_ms(_started_at, nil), do: nil

  defp duration_ms(started_at, ended_at) do
    with {started, ""} <- Integer.parse(to_string(started_at)),
         {ended, ""} <- Integer.parse(to_string(ended_at)),
         duration when duration >= 0 <- ended - started do
      duration
    else
      _other -> nil
    end
  end

  defp timestamp(nil), do: now()

  defp timestamp(value) do
    text = to_string(value)

    case Integer.parse(text) do
      {epoch_ms, ""} ->
        epoch_ms
        |> DateTime.from_unix!(:millisecond)
        |> DateTime.to_iso8601()

      _other ->
        text
    end
  end

  defp completeness(pending, opts) do
    if pending && Keyword.get(opts, :exit_status) != nil && Keyword.get(opts, :ended_at) != nil do
      "complete"
    else
      "partial"
    end
  end

  defp default_host do
    case :inet.gethostname() do
      {:ok, host} -> List.to_string(host)
      {:error, _reason} -> "unknown"
    end
  end

  defp now do
    DateTime.utc_now()
    |> DateTime.truncate(:microsecond)
    |> DateTime.to_iso8601()
  end
end
