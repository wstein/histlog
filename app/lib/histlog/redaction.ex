defmodule Histlog.Redaction do
  @moduledoc """
  Redacts common secret values before events are persisted.
  """

  @redacted "[REDACTED]"

  @patterns [
    ~r/AKIA[0-9A-Z]{16}/,
    ~r/aws_secret_access_key\s*=\s*[A-Za-z0-9\/+=]{20,}/i,
    ~r/(token|secret|password|passwd|api[_-]?key)=([^ \t\n;&]+)/i,
    ~r/(Bearer\s+)[A-Za-z0-9._~+\/=-]{16,}/i
  ]

  @doc """
  Redacts secret-looking values from nested maps and lists.

  Returns `{redacted_value, changed?}`.
  """
  def redact(value) do
    {redacted, changed?} = redact_value(value)
    {redacted, changed?}
  end

  defp redact_value(value) when is_binary(value) do
    redacted =
      Enum.reduce(@patterns, value, fn pattern, acc ->
        Regex.replace(pattern, acc, fn match ->
          redact_match(match)
        end)
      end)

    {redacted, redacted != value}
  end

  defp redact_value(value) when is_map(value) do
    Enum.reduce(value, {%{}, false}, fn {key, inner}, {acc, changed?} ->
      {redacted_inner, inner_changed?} = redact_value(inner)
      {Map.put(acc, key, redacted_inner), changed? or inner_changed?}
    end)
  end

  defp redact_value(value) when is_list(value) do
    {items, changed?} =
      Enum.reduce(value, {[], false}, fn inner, {acc, changed?} ->
        {redacted_inner, inner_changed?} = redact_value(inner)
        {[redacted_inner | acc], changed? or inner_changed?}
      end)

    {Enum.reverse(items), changed?}
  end

  defp redact_value(value), do: {value, false}

  defp redact_match(match) do
    cond do
      String.contains?(match, "=") ->
        [name | _rest] = String.split(match, "=", parts: 2)
        name <> "=" <> @redacted

      String.starts_with?(match, "Bearer ") ->
        "Bearer " <> @redacted

      true ->
        @redacted
    end
  end
end
