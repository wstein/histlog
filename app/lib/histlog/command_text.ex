defmodule Histlog.CommandText do
  @moduledoc """
  Command text normalization helpers.
  """

  def normalize(command) when is_binary(command), do: String.trim(command)
  def normalize(command), do: command

  def private?(command) when is_binary(command), do: String.starts_with?(command, " ")
  def private?(_command), do: false

  def normalize_row(row) when is_map(row) do
    command = row["command"]

    row
    |> Map.put("command", normalize(command))
    |> Map.put("is_private", private_value(row, command))
  end

  defp private_value(row, command) do
    if row["is_private"] in [1, true] || private?(command), do: 1, else: 0
  end
end
