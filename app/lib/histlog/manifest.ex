defmodule Histlog.Manifest do
  @moduledoc """
  Daily consolidation manifest helpers.
  """

  @empty %{
    "schema_version" => 1,
    "date" => nil,
    "sessions_processed" => [],
    "records_written" => 0,
    "exec_records_written" => 0,
    "checksum" => nil,
    "exec_checksum" => nil,
    "quarantined_sessions" => []
  }

  def empty(date) do
    %{@empty | "date" => Date.to_iso8601(date)}
  end

  def read(path, date) do
    case File.read(path) do
      {:ok, content} -> JSON.decode(content)
      {:error, :enoent} -> {:ok, empty(date)}
      {:error, reason} -> {:error, reason}
    end
  end

  def write(path, manifest) do
    Histlog.Storage.atomic_write(path, JSON.encode!(manifest) <> "\n")
  end

  def checksum(content) when is_binary(content) do
    :sha256
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end

  def processed?(manifest, session_path) do
    Path.basename(session_path) in Map.get(manifest, "sessions_processed", [])
  end

  def merge(existing, updates) do
    Map.merge(existing, updates, fn
      "sessions_processed", left, right -> Enum.uniq(left ++ right) |> Enum.sort()
      "quarantined_sessions", left, right -> left ++ right
      _key, _left, right -> right
    end)
  end
end
