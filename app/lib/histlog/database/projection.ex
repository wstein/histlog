defmodule Histlog.Database.Projection do
  @moduledoc """
  Helpers for writing normalized query-projection rows.
  """

  alias Histlog.Database

  @named_targets MapSet.new([
                   {"hosts", "name"},
                   {"shells", "name"},
                   {"ttys", "device"},
                   {"cmd_texts", "command"}
                 ])

  def upsert_named(conn, table, column, value) do
    cond do
      value in [nil, ""] ->
        {:ok, nil}

      not MapSet.member?(@named_targets, {table, column}) ->
        {:error, {:invalid_projection_target, table, column}}

      true ->
        with :ok <-
               Database.exec(conn, "INSERT OR IGNORE INTO #{table} (#{column}) VALUES (?)", [
                 value
               ]) do
          Database.query_value(conn, "SELECT id AS value FROM #{table} WHERE #{column} = ?", [
            value
          ])
        end
    end
  end

  def upsert_command_text(_conn, command) when command in [nil, ""],
    do: {:error, :missing_command}

  def upsert_command_text(conn, command),
    do: upsert_named(conn, "cmd_texts", "command", command)

  def upsert_path(_conn, nil), do: {:ok, nil}
  def upsert_path(_conn, ""), do: {:ok, nil}

  def upsert_path(conn, path) do
    type = path_type(path)

    with :ok <-
           Database.exec(
             conn,
             """
             INSERT INTO paths (path, type)
             VALUES (?, ?)
             ON CONFLICT(path) DO UPDATE SET
               type = CASE
                 WHEN paths.type = 'u' THEN excluded.type
                 ELSE paths.type
               END
             """,
             [path, type]
           ) do
      Database.query_value(conn, "SELECT id AS value FROM paths WHERE path = ?", [path])
    end
  end

  def insert_session(conn, materialized, date_string) do
    session = materialized.session
    ended = materialized.ended
    first_cwd = materialized.first_cwd

    with {:ok, host_id} <- upsert_named(conn, "hosts", "name", session["host"]),
         {:ok, shell_id} <- upsert_named(conn, "shells", "name", session["shell"]),
         {:ok, tty_id} <- upsert_named(conn, "ttys", "device", session["tty"]),
         {:ok, cwd_id} <- upsert_path(conn, first_cwd),
         :ok <-
           Database.exec(
             conn,
             """
             INSERT INTO sessions (
               session_uid, session_file, date, host_id, shell_id, tty_id, cwd_id,
               pid, parent_pid, started_at, ended_at
             )
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(session_uid) DO UPDATE SET
               session_file = excluded.session_file,
               date = excluded.date,
               host_id = excluded.host_id,
               shell_id = excluded.shell_id,
               tty_id = excluded.tty_id,
               cwd_id = excluded.cwd_id,
               pid = excluded.pid,
               parent_pid = excluded.parent_pid,
               started_at = excluded.started_at,
               ended_at = excluded.ended_at
             """,
             [
               session["session_id"],
               materialized.basename,
               date_string,
               host_id,
               shell_id,
               tty_id,
               cwd_id,
               session["process_id"],
               session["parent_process_id"],
               session["timestamp"],
               ended["timestamp"]
             ]
           ) do
      Database.query_value(conn, "SELECT id AS value FROM sessions WHERE session_uid = ?", [
        session["session_id"]
      ])
    end
  end

  def insert_session_command(conn, session_row_id, date_string, row) do
    with {:ok, cmd_text_id} <- upsert_command_text(conn, row["command"]),
         {:ok, cwd_id} <- upsert_path(conn, row["cwd"]) do
      Database.exec(
        conn,
        """
        INSERT INTO commands (
          session_id, exec_id, import_batch_id, import_row_index, date,
          cmd_text_id, cwd_id, timestamp, duration_ms, exit_status,
          completeness, source, is_private, is_assisted
        )
        VALUES (?, ?, NULL, NULL, ?, ?, ?, ?, ?, ?, ?, 'session', ?, ?)
        ON CONFLICT(session_id, exec_id) DO UPDATE SET
          date = excluded.date,
          cmd_text_id = excluded.cmd_text_id,
          cwd_id = excluded.cwd_id,
          timestamp = excluded.timestamp,
          duration_ms = excluded.duration_ms,
          exit_status = excluded.exit_status,
          completeness = excluded.completeness,
          source = excluded.source,
          is_private = excluded.is_private,
          is_assisted = excluded.is_assisted
        """,
        [
          session_row_id,
          row["exec_id"],
          date_string,
          cmd_text_id,
          cwd_id,
          row["timestamp"],
          row["duration_ms"],
          row["exit_status"],
          row["completeness"] || "unknown",
          private?(row["command"]),
          assisted?(row)
        ]
      )
    end
  end

  def insert_import_command(conn, date_string, event, report, index) do
    with {:ok, cmd_text_id} <- upsert_command_text(conn, event["command"]),
         {:ok, cwd_id} <- upsert_path(conn, event["cwd"]),
         {:ok, shell_id} <- upsert_named(conn, "shells", "name", import_shell(report["source"])) do
      Database.exec(
        conn,
        """
        INSERT INTO commands (
          session_id, exec_id, import_batch_id, import_row_index, date,
          cmd_text_id, cwd_id, timestamp, duration_ms, exit_status,
          completeness, source, is_private, is_assisted, import_shell_id
        )
        VALUES (NULL, NULL, ?, ?, ?, ?, ?, ?, NULL, ?, 'partial', 'import', ?, 0, ?)
        ON CONFLICT(import_batch_id, import_row_index) DO UPDATE SET
          date = excluded.date,
          cmd_text_id = excluded.cmd_text_id,
          cwd_id = excluded.cwd_id,
          timestamp = excluded.timestamp,
          exit_status = excluded.exit_status,
          completeness = excluded.completeness,
          source = excluded.source,
          is_private = excluded.is_private,
          import_shell_id = excluded.import_shell_id
        """,
        [
          report["import_batch_id"],
          index,
          date_string,
          cmd_text_id,
          cwd_id,
          event["timestamp"],
          event["exit_status"],
          private?(event["command"]),
          shell_id
        ]
      )
    end
  end

  defp path_type(path) do
    cond do
      File.dir?(path) -> "d"
      File.regular?(path) -> "f"
      true -> "u"
    end
  end

  defp private?(command) when is_binary(command) do
    if String.starts_with?(command, " "), do: 1, else: 0
  end

  defp private?(_command), do: 0

  defp assisted?(%{"assisted" => true}), do: 1
  defp assisted?(_row), do: 0

  defp import_shell(source) when source in ["zsh_history", "zsh"], do: "zsh"
  defp import_shell(source) when source in ["bash_history", "bash"], do: "bash"
  defp import_shell(source) when source in ["fish_history", "fish"], do: "fish"
  defp import_shell(_source), do: nil
end
