defmodule Histlog.Import do
  @moduledoc """
  Import helpers that model external history as synthetic histlog events.
  """

  alias Histlog.Event

  @doc """
  Builds an import batch event stream from simple execution maps.
  """
  def batch(session_id, source, import_batch_id, executions) when is_list(executions) do
    started =
      Event.new!("import_batch_started", 1, %{
        "session_id" => session_id,
        "source" => source,
        "import_batch_id" => import_batch_id
      })

    imported =
      executions
      |> Enum.with_index(2)
      |> Enum.map(fn {execution, seq} ->
        Event.new!(
          "imported_execution",
          seq,
          Map.take(execution, ["command", "cwd", "timestamp", "exit_status"])
        )
      end)

    finished =
      Event.new!("import_batch_finished", length(executions) + 2, %{
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
    executions =
      content
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)
      |> Enum.filter(&(&1["event"] in ["execution_observed", "imported_execution"]))
      |> Enum.map(&event_to_imported_execution/1)

    {:ok, executions}
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
      |> zsh_history_lines()
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
    {executions, pending_timestamp, current_lines} =
      content
      |> String.split("\n", trim: true)
      |> Enum.reduce({[], nil, []}, fn line, {executions, pending_timestamp, current_lines} ->
        if String.match?(line, ~r/^#\d+$/) do
          executions = flush_bash_execution(executions, pending_timestamp, current_lines)
          {executions, line |> String.trim_leading("#") |> parse_epoch(), []}
        else
          current_lines = current_lines ++ [line]

          if command_complete?(Enum.join(current_lines, "\n")) do
            {[imported_execution(Enum.join(current_lines, "\n"), pending_timestamp) | executions],
             nil, []}
          else
            {executions, pending_timestamp, current_lines}
          end
        end
      end)

    executions = flush_bash_execution(executions, pending_timestamp, current_lines)
    _unused = pending_timestamp
    {:ok, Enum.reverse(executions)}
  end

  defp zsh_history_lines(content) do
    {records, current} =
      content
      |> String.split("\n", trim: true)
      |> Enum.reduce({[], nil}, fn line, {records, current} ->
        cond do
          String.starts_with?(line, ": ") ->
            records = flush_line_record(records, current)
            {records, line}

          current && !command_complete?(zsh_command(current)) ->
            {records, current <> "\n" <> line}

          true ->
            records = flush_line_record(records, current)
            {records, line}
        end
      end)

    records
    |> flush_line_record(current)
    |> Enum.reverse()
  end

  defp flush_bash_execution(executions, _pending_timestamp, []), do: executions

  defp flush_bash_execution(executions, pending_timestamp, current_lines) do
    [imported_execution(Enum.join(current_lines, "\n"), pending_timestamp) | executions]
  end

  defp flush_line_record(records, nil), do: records
  defp flush_line_record(records, record), do: [record | records]

  defp zsh_command(": " <> rest) do
    case String.split(rest, ";", parts: 2) do
      [_prefix, command] -> command
      _other -> rest
    end
  end

  defp zsh_command(command), do: command

  defp command_complete?(command) do
    balanced?(command, "'") && balanced?(command, "\"")
  end

  defp balanced?(command, quote) do
    command
    |> count_unescaped(quote)
    |> rem(2)
    |> Kernel.==(0)
  end

  defp count_unescaped(command, quote) do
    command
    |> String.graphemes()
    |> Enum.reduce({0, false}, fn
      "\\", {count, false} -> {count, true}
      ^quote, {count, false} -> {count + 1, false}
      _char, {count, _escaped?} -> {count, false}
    end)
    |> elem(0)
  end

  defp parse_fish_history(content) do
    {records, current} =
      content
      |> String.split("\n", trim: true)
      |> Enum.reduce({[], %{}}, fn line, {records, current} ->
        cond do
          String.starts_with?(line, "- cmd: ") ->
            records = flush_fish_record(records, current)
            {records, %{"command" => parse_fish_scalar(String.trim_leading(line, "- cmd: "))}}

          String.starts_with?(line, "  when: ") ->
            timestamp =
              line
              |> String.trim_leading("  when: ")
              |> parse_epoch()

            {records, Map.put(current, "timestamp", timestamp)}

          String.starts_with?(line, "  paths:") ->
            {records, current}

          String.starts_with?(line, "    - ") ->
            cwd = line |> String.trim_leading("    - ") |> parse_fish_scalar()
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
      "timestamp" => Map.get(event, "timestamp", Map.get(event, "started_at")),
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

  defp parse_fish_scalar(value) do
    value
    |> String.trim()
    |> decode_fish_escapes()
  end

  defp decode_fish_escapes("\"" <> rest) do
    rest
    |> String.slice(0, String.length(rest) - 1)
    |> String.replace("\\\"", "\"")
    |> String.replace("\\\\n", "\n")
    |> String.replace("\\\\t", "\t")
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\\\", "\\")
  end

  defp decode_fish_escapes(value), do: value
end
