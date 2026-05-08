defmodule Histlog.Storage do
  @moduledoc """
  File IO boundary for histlog session streams and materialized outputs.
  """

  alias Histlog.Event

  @default_root Path.expand("~/.local/share/histlog")

  @doc """
  Returns the configured histlog data root.
  """
  def root(opts \\ []) do
    Keyword.get(opts, :root, @default_root)
  end

  @doc """
  Creates the v1 directory layout.
  """
  def ensure_layout(root, _date \\ nil) do
    [
      live_dir(root),
      closed_dir(root),
      quarantine_dir(root),
      hook_state_dir(root),
      imports_dir(root),
      exports_dir(root)
    ]
    |> Enum.each(&File.mkdir_p!/1)

    :ok
  end

  def live_dir(root, _date \\ nil), do: Path.join([root, "sessions", "live"])
  def closed_dir(root, _date \\ nil), do: Path.join([root, "sessions", "closed"])

  def quarantine_dir(root, _date \\ nil), do: Path.join([root, "sessions", "quarantine"])

  def imports_dir(root), do: Path.join(root, "imports")
  def exports_dir(root), do: Path.join(root, "exports")
  def hook_state_dir(root), do: Path.join(root, "hook-state")

  def database_path(root), do: Path.join(root, "histlog.db")

  @doc """
  Builds the operator-facing session filename.
  """
  def session_filename(date, host, process_id, start_ns) do
    safe_host =
      host
      |> String.replace(~r/[^A-Za-z0-9_.-]/, "_")
      |> String.trim("_")

    "session-#{Date.to_iso8601(date)}-#{safe_host}-#{process_id}-#{start_ns}.ndjson"
  end

  @doc """
  Appends one validated event to a session stream.
  """
  def append_event(path, event, opts \\ []) do
    line = Event.encode_line!(event)
    sync? = Keyword.get(opts, :sync?, true)
    File.mkdir_p!(Path.dirname(path))

    with {:ok, :ok} <-
           File.open(path, [:append, :binary], fn io ->
             IO.binwrite(io, line)
             if sync?, do: :file.sync(io), else: :ok
           end) do
      :ok
    end
  end

  @doc """
  Moves a live session file to its closed path.
  """
  def close_session(live_path, closed_path) do
    File.mkdir_p!(Path.dirname(closed_path))
    File.rename(live_path, closed_path)
  end

  @doc """
  Writes a file through a temp file and atomic rename.
  """
  def atomic_write(path, content) when is_binary(content) do
    File.mkdir_p!(Path.dirname(path))
    tmp_path = path <> ".tmp-" <> unique_suffix()

    with :ok <- File.write(tmp_path, content, [:binary]),
         :ok <- sync_path(tmp_path),
         :ok <- File.rename(tmp_path, path) do
      :ok
    else
      {:error, reason} = error ->
        File.rm(tmp_path)
        {:error, reason || error}
    end
  end

  @doc """
  Reads and decodes all events in a session file.
  """
  def read_events(path) do
    with {:ok, content} <- File.read(path) do
      Histlog.NDJSON.decode(content)
    end
  end

  @doc """
  Moves a malformed session into quarantine.
  """
  def quarantine_session(path, root, date) do
    destination = Path.join(quarantine_dir(root, date), Path.basename(path))
    File.mkdir_p!(Path.dirname(destination))

    case File.rename(path, destination) do
      :ok -> {:ok, destination}
      {:error, :exdev} -> copy_then_remove(path, destination)
      {:error, reason} -> {:error, reason}
    end
  end

  defp copy_then_remove(path, destination) do
    with {:ok, _bytes} <- File.copy(path, destination),
         :ok <- File.rm(path) do
      {:ok, destination}
    end
  end

  defp sync_path(path) do
    with {:ok, :ok} <- File.open(path, [:read, :binary], &:file.sync/1) do
      :ok
    end
  end

  defp unique_suffix do
    8
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
