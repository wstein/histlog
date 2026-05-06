defmodule Histlog.Event do
  @moduledoc """
  Construction and NDJSON conversion for canonical histlog events.
  """

  alias Histlog.Redaction
  alias Histlog.Schema
  alias Histlog.Event.Types

  @schema_version Histlog.schema_version()

  @doc """
  Builds a redacted canonical event map.
  """
  def new(event, seq, attrs \\ %{}) when is_binary(event) do
    timestamp = Map.get(attrs, "timestamp") || now()

    base = %{
      "schema_version" => @schema_version,
      "event" => event,
      "seq" => seq,
      "timestamp" => timestamp
    }

    attrs = Map.delete(attrs, "timestamp")
    {redacted, changed?} = Redaction.redact(Map.merge(base, attrs))

    event =
      if changed? do
        Map.put(redacted, "redacted", true)
      else
        redacted
      end

    case Schema.validate_event(event) do
      :ok -> {:ok, event}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Builds a redacted canonical event or raises on validation failure.
  """
  def new!(event, seq, attrs \\ %{}) do
    case new(event, seq, attrs) do
      {:ok, built} -> built
      {:error, reason} -> raise ArgumentError, "invalid histlog event: #{inspect(reason)}"
    end
  end

  @doc """
  Encodes an event as one NDJSON line.
  """
  def encode_line!(event) when is_map(event) do
    :ok = Schema.validate_event!(event)
    JSON.encode!(event) <> "\n"
  end

  @doc """
  Decodes one NDJSON line into an event map.
  """
  def decode_line(line) when is_binary(line) do
    with {:ok, decoded} <- JSON.decode(String.trim_trailing(line, "\n")),
         :ok <- Schema.validate_event(decoded) do
      {:ok, decoded}
    else
      {:error, reason} -> {:error, reason}
      exception when is_exception(exception) -> {:error, exception}
    end
  end

  @doc """
  Converts a canonical event map to an internal typed event struct.
  """
  def to_typed(event), do: Types.from_map(event)

  @doc """
  Converts an internal typed event struct back to a canonical event map.
  """
  def from_typed(event), do: Types.to_map(event)

  defp now do
    DateTime.utc_now()
    |> DateTime.truncate(:microsecond)
    |> DateTime.to_iso8601()
  end
end
