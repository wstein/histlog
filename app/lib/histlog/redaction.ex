defmodule Histlog.Redaction do
  @moduledoc """
  Redacts common secret values before events are persisted.
  """

  @redacted "[REDACTED]"

  @doc """
  Redacts secret-looking values from nested maps and lists.

  Returns `{redacted_value, changed?}`.
  """
  def redact(value) do
    {redacted, changed?} = redact_value(value)
    {redacted, changed?}
  end

  defp redact_value(value) when is_binary(value) do
    redacted = redact_string(value)

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

  defp redact_string(value) do
    value
    |> replace(~r/AKIA[0-9A-Z]{16}/, @redacted)
    |> replace(~r/(Bearer\s+)[A-Za-z0-9._~+\/=-]{16,}/i, "\\1" <> @redacted)
    |> replace(
      ~r/(aws_secret_access_key\s*=\s*)(['"]?)[A-Za-z0-9\/+=]{20,}\2/i,
      "\\1\\2" <> @redacted <> "\\2"
    )
    |> replace(
      ~r/(aws\s+configure\s+set\s+aws_secret_access_key\s+)(['"]?)[A-Za-z0-9\/+=]{20,}\2/i,
      "\\1\\2" <> @redacted <> "\\2"
    )
    |> redact_named_assignments()
    |> redact_separated_arguments()
    |> redact_label_values()
  end

  defp replace(value, regex, replacement), do: Regex.replace(regex, value, replacement)

  defp redact_named_assignments(value) do
    Regex.replace(
      ~r/\b(token|secret|password|passwd|api[_-]?key)(\s*=\s*)(['"]?)([^'"\s;&]{8,})\3/i,
      value,
      "\\1\\2\\3" <> @redacted <> "\\3"
    )
  end

  defp redact_separated_arguments(value) do
    Regex.replace(
      ~r/\b(token|secret|password|passwd|api[_-]?key)(\s+)(['"]?)([^'"\s;&]{8,})\3/i,
      value,
      "\\1\\2\\3" <> @redacted <> "\\3"
    )
  end

  defp redact_label_values(value) do
    Regex.replace(
      ~r/\b(token|secret|password|passwd|api[_-]?key)(\s*:\s*)(['"]?)([^'"\s;&]{8,})\3/i,
      value,
      "\\1\\2\\3" <> @redacted <> "\\3"
    )
  end
end
