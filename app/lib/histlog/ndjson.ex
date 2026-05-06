defmodule Histlog.NDJSON do
  @moduledoc """
  Line-oriented NDJSON helpers for histlog event streams.
  """

  alias Histlog.Event

  @doc """
  Encodes events into an NDJSON binary.
  """
  def encode!(events) when is_list(events) do
    Enum.map_join(events, "", &Event.encode_line!/1)
  end

  @doc """
  Decodes an NDJSON binary.
  """
  def decode(ndjson) when is_binary(ndjson) do
    ndjson
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, events} ->
      case Event.decode_line(line) do
        {:ok, event} -> {:cont, {:ok, [event | events]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, events} -> {:ok, Enum.reverse(events)}
      {:error, reason} -> {:error, reason}
    end
  end
end
