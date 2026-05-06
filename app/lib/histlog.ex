defmodule Histlog do
  @moduledoc """
  Log-structured shell history built from append-only NDJSON event streams.
  """

  @schema_version 1

  @doc """
  Returns the canonical histlog event schema version.
  """
  def schema_version, do: @schema_version
end
