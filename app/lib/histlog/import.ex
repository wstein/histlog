defmodule Histlog.Import do
  @moduledoc """
  Import helpers that model external history as synthetic histlog events.
  """

  alias Histlog.Database
  alias Histlog.Database.Projection
  alias Histlog.Database.Schema
  alias Histlog.Event
  alias Histlog.Storage

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
    {executions, _warnings} = parse_ndjson(content)
    {:ok, executions}
  end

  def parse(source, _content), do: {:error, {:unsupported_import_source, source}}

  @doc """
  Parses source history and returns executions with diagnostics.
  """
  def parse_with_report(source, content) do
    case source do
      "ndjson" ->
        {executions, warnings} = parse_ndjson(content)
        {:ok, %{executions: executions, warnings: warnings}}

      source ->
        with {:ok, executions} <- parse(source, content) do
          {:ok, %{executions: executions, warnings: []}}
        end
    end
  end

  @doc """
  Parses source history and wraps it in import batch events.
  """
  def from_source(session_id, source, import_batch_id, content) do
    with {:ok, executions} <- parse(source, content) do
      {:ok, batch(session_id, source, import_batch_id, executions)}
    end
  end

  @doc """
  Parses source history, wraps it in events, and returns an import diagnostics report.
  """
  def from_source_with_report(session_id, source, import_batch_id, content) do
    with {:ok, %{executions: executions, warnings: warnings}} <-
           parse_with_report(source, content) do
      events = batch(session_id, source, import_batch_id, executions)

      report = %{
        "schema_version" => Histlog.schema_version(),
        "source" => source,
        "session_id" => session_id,
        "import_batch_id" => import_batch_id,
        "records" => length(executions),
        "warnings" => warnings
      }

      {:ok, events, report}
    end
  end

  @doc """
  Materializes an import event stream into the SQLite query projection.
  """
  def materialize(root, date, source_path, events, report) do
    Storage.ensure_layout(root, date)

    Database.with_connection(root, fn conn ->
      with :ok <- Schema.ensure(conn) do
        Database.transaction(conn, fn ->
          materialize_in_transaction(conn, root, date, source_path, events, report)
        end)
      end
    end)
  end

  defp materialize_in_transaction(conn, root, date, source_path, events, report) do
    import_batch_id = report["import_batch_id"]

    with :ok <- delete_import_batch(conn, import_batch_id),
         :ok <- insert_import_batch(conn, source_path, report),
         :ok <- insert_imported_execution_rows(conn, date, events, report) do
      {:ok,
       %{
         "database_path" => Storage.database_path(root),
         "import_batch_id" => import_batch_id,
         "records_materialized" => report["records"]
       }}
    end
  end

  defp delete_import_batch(conn, import_batch_id) do
    with :ok <-
           Database.exec(
             conn,
             """
             DELETE FROM command_paths
             WHERE command_id IN (
               SELECT id FROM commands WHERE import_batch_id = ?
             )
             """,
             [import_batch_id]
           ),
         :ok <-
           Database.exec(conn, "DELETE FROM commands WHERE import_batch_id = ?", [
             import_batch_id
           ]),
         :ok <-
           Database.exec(conn, "DELETE FROM imports WHERE import_batch_id = ?", [import_batch_id]) do
      :ok
    end
  end

  defp insert_import_batch(conn, source_path, report) do
    Database.exec(
      conn,
      """
      INSERT INTO imports (
        import_batch_id, source, source_path, imported_at, records_count,
        warnings_count, report_json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """,
      [
        report["import_batch_id"],
        report["source"],
        source_path,
        DateTime.utc_now() |> DateTime.to_iso8601(),
        report["records"],
        length(report["warnings"] || []),
        JSON.encode!(report)
      ]
    )
  end

  defp insert_imported_execution_rows(conn, date, events, report) do
    events
    |> Enum.filter(&(&1["event"] == "imported_execution"))
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {event, index}, :ok ->
      case insert_imported_execution_row(conn, date, event, report, index) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_imported_execution_row(conn, date, event, report, index) do
    Projection.insert_import_command(conn, Date.to_iso8601(date), event, report, index)
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

  defp parse_ndjson(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.with_index(1)
    |> Enum.reduce({[], []}, fn {line, line_number}, {executions, warnings} ->
      case JSON.decode(line) do
        {:ok, %{"event" => event} = decoded}
        when event in ["execution_observed", "imported_execution"] ->
          {[event_to_imported_execution(decoded) | executions], warnings}

        {:ok, _decoded} ->
          {executions, warnings}

        {:error, reason} ->
          warning = %{
            "line" => line_number,
            "reason" => inspect(reason)
          }

          {executions, [warning | warnings]}
      end
    end)
    |> then(fn {executions, warnings} -> {Enum.reverse(executions), Enum.reverse(warnings)} end)
  end

  defp imported_execution(command, timestamp, cwd \\ nil) do
    %{
      "command" => utf8_safe(command),
      "cwd" => utf8_safe(cwd),
      "timestamp" => utf8_safe(timestamp),
      "exit_status" => nil
    }
  end

  defp utf8_safe(nil), do: nil

  defp utf8_safe(value) when is_binary(value) do
    case :unicode.characters_to_binary(value, :utf8, :utf8) do
      safe when is_binary(safe) -> safe
      {:error, valid, rest} -> valid <> "?" <> utf8_safe(drop_invalid_byte(rest))
      {:incomplete, valid, _rest} -> valid <> "?"
    end
  end

  defp utf8_safe(value), do: value

  defp drop_invalid_byte(<<_byte, rest::binary>>), do: rest
  defp drop_invalid_byte(_), do: ""

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
