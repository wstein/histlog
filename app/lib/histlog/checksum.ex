defmodule Histlog.Checksum do
  @moduledoc """
  Hash helpers for materialization integrity metadata.
  """

  def sha256(content) when is_binary(content) do
    :sha256
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end
end
