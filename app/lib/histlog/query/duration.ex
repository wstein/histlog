defmodule Histlog.Query.Duration do
  @moduledoc false

  @shortcuts %{
    fast: {:lt, 100},
    instant: {:lt, 10},
    quick: {:lt, 1_000},
    slow: {:gt, 10_000},
    background: {:gt, 60_000}
  }

  def validate(nil), do: :ok

  def validate(value) do
    case parse(value) do
      {:ok, _filter} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def filter(opts) do
    shortcut =
      Enum.find_value(@shortcuts, fn {flag, filter} ->
        if Keyword.get(opts, flag, false), do: filter
      end)

    case {shortcut, parse(Keyword.get(opts, :duration))} do
      {nil, {:ok, filter}} -> filter
      {nil, nil} -> nil
      {filter, _duration} -> filter
    end
  end

  def match?(_row, nil), do: true
  def match?(%{"duration_ms" => nil}, _duration), do: false
  def match?(row, {:lt, ms}), do: row["duration_ms"] < ms
  def match?(row, {:gt, ms}), do: row["duration_ms"] > ms
  def match?(row, {:eq, ms}), do: row["duration_ms"] == ms

  defp parse(nil), do: nil

  defp parse(value) do
    {operator, value} =
      case value do
        ">" <> rest -> {:gt, rest}
        "<" <> rest -> {:lt, rest}
        other -> {:eq, other}
      end

    case duration_ms(value) do
      {:ok, ms} -> {:ok, {operator, ms}}
      :error -> {:error, "invalid duration #{inspect(value)}"}
    end
  end

  defp duration_ms(value) do
    case Regex.run(~r/^([0-9]+(?:\.[0-9]+)?)(ms|s|m|h|d|w)?$/, String.trim(value)) do
      [_, number, unit] ->
        multiplier = %{
          "ms" => 1,
          "s" => 1_000,
          "" => 1_000,
          "m" => 60_000,
          "h" => 3_600_000,
          "d" => 86_400_000,
          "w" => 604_800_000
        }

        {parsed, ""} = Float.parse(number)
        {:ok, round(parsed * Map.fetch!(multiplier, unit || ""))}

      _ ->
        :error
    end
  end
end
