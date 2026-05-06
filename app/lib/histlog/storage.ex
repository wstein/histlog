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
  Creates the v1 directory layout for a date.
  """
  def ensure_layout(root, date) do
    [
      live_dir(root, date),
      closed_dir(root, date),
      quarantine_dir(root, date),
      hook_state_dir(root),
      daily_dir(root),
      imports_dir(root),
      exports_dir(root),
      manifests_dir(root)
    ]
    |> Enum.each(&File.mkdir_p!/1)

    :ok
  end

  def live_dir(root, date), do: Path.join([root, "sessions", "live", Date.to_iso8601(date)])
  def closed_dir(root, date), do: Path.join([root, "sessions", "closed", Date.to_iso8601(date)])

  def quarantine_dir(root, date),
    do: Path.join([root, "sessions", "quarantine", Date.to_iso8601(date)])

  def daily_dir(root), do: Path.join(root, "daily")
  def imports_dir(root), do: Path.join(root, "imports")
  def exports_dir(root), do: Path.join(root, "exports")
  def manifests_dir(root), do: Path.join(root, "manifests")
  def hook_state_dir(root), do: Path.join(root, "hook-state")

  def daily_events_path(root, date),
    do: Path.join(daily_dir(root), Date.to_iso8601(date) <> ".ndjson")

  def daily_exec_path(root, date),
    do: Path.join(daily_dir(root), Date.to_iso8601(date) <> ".exec.ndjson")

  def manifest_path(root, date),
    do: Path.join(manifests_dir(root), Date.to_iso8601(date) <> ".json")

  @doc """
  Builds the operator-facing session filename.
  """
  def session_filename(host, process_id, start_ns) do
    safe_host =
      host
      |> String.replace(~r/[^A-Za-z0-9_.-]/, "_")
      |> String.trim("_")

    "session-#{safe_host}-#{process_id}-#{start_ns}.ndjson"
  end

  @doc """
  Appends one validated event to a session stream and fsyncs it.
  """
  def append_event(path, event) do
    line = Event.encode_line!(event)
    File.mkdir_p!(Path.dirname(path))

    with {:ok, :ok} <-
           File.open(path, [:append, :binary], fn io ->
             IO.binwrite(io, line)
             :file.sync(io)
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
