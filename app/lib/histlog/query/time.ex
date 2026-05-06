defmodule Histlog.Query.Time do
  @moduledoc false

  def filter(opts) do
    cond do
      Keyword.get(opts, :week, false) ->
        today = local_today()
        {Date.add(today, -Date.day_of_week(today) + 1) |> Date.to_iso8601(), nil}

      Keyword.get(opts, :today, false) ->
        today = local_today() |> Date.to_iso8601()
        {today, today <> "T23:59:59"}

      Keyword.get(opts, :yesterday, false) ->
        yesterday = local_today() |> Date.add(-1) |> Date.to_iso8601()
        {yesterday, yesterday <> "T23:59:59"}

      time = Keyword.get(opts, :time) ->
        parse_range(time)

      since = Keyword.get(opts, :since) ->
        {normalize(since), normalize(Keyword.get(opts, :before))}

      before = Keyword.get(opts, :before) ->
        {nil, normalize(before)}

      true ->
        nil
    end
  end

  def match?(_row, nil), do: true

  def match?(row, {since, before}) do
    value = comparable(row["timestamp"])
    after_since? = is_nil(since) || (!is_nil(value) && value >= since)
    before_before? = is_nil(before) || (!is_nil(value) && value <= before)
    after_since? && before_before?
  end

  def comparable(nil), do: nil
  def comparable(value), do: local_timestamp(value)

  def local_timestamp(timestamp) do
    with {:ok, datetime, _offset} <- DateTime.from_iso8601(to_string(timestamp)) do
      datetime
      |> DateTime.to_unix(:second)
      |> :calendar.system_time_to_local_time(:second)
      |> format_local_time()
    else
      _error ->
        timestamp
        |> to_string()
        |> String.replace(" ", "T")
        |> String.replace_suffix("Z", "")
        |> String.slice(0, 19)
    end
  end

  defp parse_range(value) do
    cond do
      Regex.match?(~r/^\d+w$/, value) ->
        weeks = value |> String.trim_trailing("w") |> String.to_integer()
        {Date.add(local_today(), -7 * weeks) |> Date.to_iso8601(), nil}

      String.contains?(value, "..") ->
        [since, before] = String.split(value, "..", parts: 2)

        {blank_to_nil(since) && normalize(since), blank_to_nil(before) && normalize(before)}

      true ->
        {normalize(value), nil}
    end
  end

  defp normalize(nil), do: nil

  defp normalize(value) do
    value = String.trim(value)

    cond do
      Regex.match?(~r/^\d{2}:\d{2}/, value) -> Date.to_iso8601(local_today()) <> "T#{value}"
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, value) -> value
      true -> String.replace(value, " ", "T")
    end
  end

  defp local_today do
    {{year, month, day}, _time} = :calendar.local_time()
    Date.new!(year, month, day)
  end

  defp format_local_time({{year, month, day}, {hour, minute, second}}) do
    [
      pad(year, 4),
      "-",
      pad(month, 2),
      "-",
      pad(day, 2),
      "T",
      pad(hour, 2),
      ":",
      pad(minute, 2),
      ":",
      pad(second, 2)
    ]
    |> IO.iodata_to_binary()
  end

  defp pad(value, count), do: value |> Integer.to_string() |> String.pad_leading(count, "0")

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
