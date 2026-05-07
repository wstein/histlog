defmodule Histlog.Query.Commands do
  @moduledoc """
  Command discovery summaries derived from query execution rows.
  """

  def rows(execution_rows, opts \\ []) do
    with {:ok, matcher} <- matcher(Keyword.get(opts, :search, ""), opts) do
      rows =
        execution_rows
        |> Enum.filter(&match_row?(&1, matcher))
        |> Enum.filter(&session_match?(&1, Keyword.get(opts, :session)))
        |> Enum.filter(&directory_match?(&1, Keyword.get(opts, :dir)))
        |> Enum.group_by(& &1["command"])
        |> Enum.reject(fn {command, _rows} -> !is_binary(command) || command == "" end)
        |> Enum.map(fn {command, rows} -> summarize(command, rows) end)
        |> sort_rows(opts)
        |> limit_rows(Keyword.get(opts, :limit))

      {:ok, rows}
    end
  end

  defp matcher(nil, _opts), do: {:ok, {:all, nil}}
  defp matcher("", _opts), do: {:ok, {:all, nil}}

  defp matcher(search, opts) do
    cond do
      Keyword.get(opts, :regex, false) ->
        case Regex.compile(search) do
          {:ok, regex} -> {:ok, {:regex, regex}}
          {:error, {reason, position}} -> {:error, "invalid regex at #{position}: #{reason}"}
          {:error, reason} -> {:error, "invalid regex: #{inspect(reason)}"}
        end

      Keyword.get(opts, :fuzzy, false) ->
        {:ok, {:fuzzy, String.downcase(search)}}

      true ->
        {:ok, {:contains, String.downcase(search)}}
    end
  end

  defp match_row?(_row, {:all, nil}), do: true

  defp match_row?(%{"command" => command}, {:contains, search}) when is_binary(command) do
    command |> String.downcase() |> String.contains?(search)
  end

  defp match_row?(%{"command" => command}, {:regex, regex}) when is_binary(command) do
    Regex.match?(regex, command)
  end

  defp match_row?(%{"command" => command}, {:fuzzy, search}) when is_binary(command) do
    fuzzy_match?(String.downcase(command), search)
  end

  defp match_row?(_row, _matcher), do: false

  defp fuzzy_match?(_command, ""), do: true

  defp fuzzy_match?(command, search) do
    search
    |> String.graphemes()
    |> Enum.reduce_while(command, fn needle, rest ->
      case :binary.match(rest, needle) do
        {index, length} ->
          {:cont, binary_part(rest, index + length, byte_size(rest) - index - length)}

        :nomatch ->
          {:halt, false}
      end
    end)
    |> then(&(&1 != false))
  end

  defp session_match?(_row, nil), do: true

  defp session_match?(%{"session_id" => session_id}, session),
    do: to_string(session_id) == session

  defp session_match?(_row, _session), do: false

  defp directory_match?(_row, nil), do: true

  defp directory_match?(%{"cwd" => cwd}, directory) when is_binary(cwd) and cwd != "" do
    Path.expand(cwd) == Path.expand(directory)
  end

  defp directory_match?(_row, _directory), do: false

  defp summarize(command, rows) do
    timestamps = rows |> Enum.map(& &1["timestamp"]) |> Enum.reject(&is_nil/1) |> Enum.sort()
    sessions = rows |> Enum.map(& &1["session_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    directories = rows |> Enum.map(& &1["cwd"]) |> Enum.reject(&blank?/1) |> Enum.uniq()

    %{
      command: command,
      count: length(rows),
      first_seen: List.first(timestamps),
      last_seen: List.last(timestamps),
      sessions: length(sessions),
      directories: length(directories),
      successes: Enum.count(rows, &(&1["exit_status"] == 0)),
      failures: Enum.count(rows, &(is_integer(&1["exit_status"]) && &1["exit_status"] != 0))
    }
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp sort_rows(rows, opts) do
    sort_by = Keyword.get(opts, :sort_by, "recent")

    sorted =
      case sort_by do
        "alpha" ->
          Enum.sort_by(rows, &String.downcase(&1.command))

        "count" ->
          Enum.sort_by(rows, &{&1.count, &1.last_seen || ""})

        "context" ->
          Enum.sort_by(rows, &{&1.sessions + &1.directories, &1.count, &1.last_seen || ""})

        "recent" ->
          Enum.sort_by(rows, &(&1.last_seen || ""))

        _other ->
          Enum.sort_by(rows, &(&1.last_seen || ""))
      end

    cond do
      Keyword.get(opts, :asc, false) -> sorted
      Keyword.get(opts, :desc, false) -> Enum.reverse(sorted)
      sort_by in ["count", "context", "recent"] -> Enum.reverse(sorted)
      true -> sorted
    end
  end

  defp limit_rows(rows, nil), do: rows
  defp limit_rows(rows, limit) when limit < 0, do: Enum.take(rows, abs(limit))
  defp limit_rows(rows, limit), do: Enum.take(rows, limit)
end
