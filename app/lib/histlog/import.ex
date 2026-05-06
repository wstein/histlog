defmodule Histlog.Import do
  @moduledoc """
  Import helpers that model external history as synthetic histlog events.
  """

  alias Histlog.Event
  alias Histlog.NDJSON

  @doc """
  Builds an import batch event stream from simple execution maps.
  """
  def batch(session_id, source, import_batch_id, executions) when is_list(executions) do
    started =
      Event.new!("import_batch_started", session_id, 1, %{
        "source" => source,
        "import_batch_id" => import_batch_id
      })

    imported =
      executions
      |> Enum.with_index(2)
      |> Enum.map(fn {execution, seq} ->
        Event.new!(
          "imported_execution",
          session_id,
          seq,
          Map.take(execution, ["command", "cwd", "timestamp", "exit_status"])
        )
      end)

    finished =
      Event.new!("import_batch_finished", session_id, length(executions) + 2, %{
        "import_batch_id" => import_batch_id,
        "records" => length(executions)
      })

    [started | imported] ++ [finished]
  end

  @doc """
  Parses a source history file into imported execution maps.
  """
  def parse("zsh_history", content), do: parse_zsh_history(content)
  def parse("zsh", content), do: parse_zsh_history(content)
  def parse("bash_history", content), do: parse_bash_history(content)
  def parse("bash", content), do: parse_bash_history(content)
  def parse("fish_history", content), do: parse_fish_history(content)
  def parse("fish", content), do: parse_fish_history(content)

  def parse("ndjson", content) do
    with {:ok, events} <- NDJSON.decode(content) do
      executions =
        events
        |> Enum.filter(&(&1["event"] in ["execution_observed", "imported_execution"]))
        |> Enum.map(&event_to_imported_execution/1)

      {:ok, executions}
    end
  end

  def parse(source, _content), do: {:error, {:unsupported_import_source, source}}

  @doc """
  Parses source history and wraps it in import batch events.
  """
  def from_source(session_id, source, import_batch_id, content) do
    with {:ok, executions} <- parse(source, content) do
      {:ok, batch(session_id, source, import_batch_id, executions)}
    end
  end

  defp parse_zsh_history(content) do
    executions =
      content
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))
      |> Enum.map(&parse_zsh_line/1)
      |> Enum.reject(&is_nil/1)

    {:ok, executions}
  end

  defp parse_zsh_line(": " <> rest) do
    with [prefix, command] <- String.split(rest, ";", parts: 2),
         [timestamp | _duration] <- String.split(prefix, ":"),
         {epoch, ""} <- Integer.parse(String.trim(timestamp)) do
      imported_execution(command, epoch_to_iso8601(epoch))
    else
      _other -> nil
    end
  end

  defp parse_zsh_line(command), do: imported_execution(command, nil)

  defp parse_bash_history(content) do
    {executions, pending_timestamp} =
      content
      |> String.split("\n", trim: true)
      |> Enum.reduce({[], nil}, fn line, {executions, pending_timestamp} ->
        if String.match?(line, ~r/^#\d+$/) do
          {executions, line |> String.trim_leading("#") |> parse_epoch()}
        else
          {[imported_execution(line, pending_timestamp) | executions], nil}
        end
      end)

    _unused = pending_timestamp
    {:ok, Enum.reverse(executions)}
  end

  defp parse_fish_history(content) do
    {records, current} =
      content
      |> String.split("\n", trim: true)
      |> Enum.reduce({[], %{}}, fn line, {records, current} ->
        cond do
          String.starts_with?(line, "- cmd: ") ->
            records = flush_fish_record(records, current)
            {records, %{"command" => unescape_fish_value(String.trim_leading(line, "- cmd: "))}}

          String.starts_with?(line, "  when: ") ->
            timestamp =
              line
              |> String.trim_leading("  when: ")
              |> parse_epoch()

            {records, Map.put(current, "timestamp", timestamp)}

          String.starts_with?(line, "  paths:") ->
            {records, current}

          String.starts_with?(line, "    - ") ->
            cwd = line |> String.trim_leading("    - ") |> unescape_fish_value()
            {records, Map.put_new(current, "cwd", cwd)}

          true ->
            {records, current}
        end
      end)

    {:ok, records |> flush_fish_record(current) |> Enum.reverse()}
  end

  defp flush_fish_record(records, %{"command" => command} = current) do
    [
      imported_execution(command, Map.get(current, "timestamp"), Map.get(current, "cwd"))
      | records
    ]
  end

  defp flush_fish_record(records, _current), do: records

  defp event_to_imported_execution(%{"event" => "imported_execution"} = event) do
    Map.take(event, ["command", "cwd", "timestamp", "exit_status"])
  end

  defp event_to_imported_execution(%{"event" => "execution_observed"} = event) do
    %{
      "command" => Map.get(event, "command", ""),
      "cwd" => Map.get(event, "cwd"),
      "timestamp" => Map.get(event, "started_at"),
      "exit_status" => Map.get(event, "exit_status")
    }
  end

  defp imported_execution(command, timestamp, cwd \\ nil) do
    %{
      "command" => command,
      "cwd" => cwd,
      "timestamp" => timestamp,
      "exit_status" => nil
    }
  end

  defp parse_epoch(value) do
    case Integer.parse(String.trim(value)) do
      {epoch, ""} -> epoch_to_iso8601(epoch)
      _other -> nil
    end
  end

  defp epoch_to_iso8601(epoch) do
    epoch
    |> DateTime.from_unix!()
    |> DateTime.to_iso8601()
  end

  defp unescape_fish_value(value) do
    value
    |> String.trim()
    |> String.trim("\"")
    |> String.replace("\\n", "\n")
  end
end
