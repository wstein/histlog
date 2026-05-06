defmodule Histlog.Durability do
  @moduledoc false

  @modes ["safe", "balanced", "fast"]

  def modes, do: @modes

  def normalize(nil), do: {:ok, "balanced"}
  def normalize(value) when value in @modes, do: {:ok, value}
  def normalize(value) when value in [:safe, :balanced, :fast], do: {:ok, Atom.to_string(value)}

  def normalize(value),
    do: {:error, "invalid durability #{inspect(value)}; expected safe, balanced, or fast"}

  def normalize!(value) do
    case normalize(value) do
      {:ok, mode} -> mode
      {:error, reason} -> raise ArgumentError, reason
    end
  end
end
