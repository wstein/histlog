#!/usr/bin/env elixir

__ENV__.file
|> Path.dirname()
|> Path.join("../app/_build/{dev,test,prod}/lib/*/ebin")
|> Path.expand()
|> Path.wildcard()
|> Enum.each(&:code.add_patha(String.to_charlist(&1)))

defmodule Histlog.NormalizeDbPaths do
  @moduledoc false

  def main(argv \\ System.argv()) do
    {opts, args, invalid} =
      OptionParser.parse(argv,
        strict: [root: :string, db: :string, dry_run: :boolean, help: :boolean],
        aliases: [r: :root, h: :help]
      )

    cond do
      invalid != [] ->
        raise "invalid options: #{inspect(invalid)}"

      Keyword.get(opts, :help, false) ->
        IO.write(help())

      true ->
        db_path = db_path(opts, args)
        report = normalize!(db_path, Keyword.get(opts, :dry_run, false))
        IO.puts(JSON.encode!(report))
    end
  rescue
    exception ->
      IO.puts(:stderr, "normalize-db-paths: #{Exception.message(exception)}")
      System.halt(1)
  end

  defp normalize!(db_path, dry_run?) do
    load_histlog_modules!()

    unless File.exists?(db_path) do
      raise "database does not exist: #{db_path}"
    end

    backup_path = db_path <> ".paths-backup-" <> timestamp()
    File.cp!(db_path, backup_path)

    {:ok, conn} = Exqlite.Sqlite3.open(db_path)

    try do
      path_moves = path_moves(conn)
      resolved_updates = resolved_path_updates(conn)

      unless dry_run? do
        :ok =
          Histlog.Database.transaction(conn, fn ->
            with :ok <- apply_path_moves(conn, path_moves),
                 :ok <- apply_resolved_path_updates(conn, resolved_updates) do
              :ok
            end
          end)
      end

      %{
        "database" => db_path,
        "backup" => backup_path,
        "dry_run" => dry_run?,
        "path_rows_changed" => length(path_moves),
        "path_reference_updates" => Enum.count(path_moves, &(&1.action == :merge)),
        "resolved_path_rows_changed" => length(resolved_updates)
      }
    after
      Exqlite.Sqlite3.close(conn)
    end
  end

  defp path_moves(conn) do
    {:ok, rows} = Histlog.Database.query_maps(conn, "SELECT id, path, type FROM paths ORDER BY id")

    existing =
      Map.new(rows, fn %{id: id, path: path} -> {path, id} end)

    rows
    |> Enum.map(fn row ->
      normalized = Histlog.PathNormalizer.normalize(row.path)
      target_id = Map.get(existing, normalized)

      cond do
        normalized == row.path ->
          nil

        is_integer(target_id) and target_id != row.id ->
          Map.merge(row, %{normalized: normalized, target_id: target_id, action: :merge})

        true ->
          Map.merge(row, %{normalized: normalized, target_id: nil, action: :rename})
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp resolved_path_updates(conn) do
    if table_column?(conn, "command_paths", "resolved_path") do
      {:ok, rows} =
        Histlog.Database.query_maps(
          conn,
          "SELECT id, resolved_path FROM command_paths ORDER BY id"
        )

      rows
      |> Enum.map(fn row -> Map.put(row, :normalized, Histlog.PathNormalizer.normalize(row.resolved_path)) end)
      |> Enum.reject(&(&1.normalized == &1.resolved_path))
    else
      []
    end
  end

  defp apply_path_moves(conn, moves) do
    Enum.reduce_while(moves, :ok, fn move, :ok ->
      result =
        case move.action do
          :merge -> merge_path(conn, move)
          :rename -> rename_path(conn, move)
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp merge_path(conn, move) do
    with :ok <- maybe_upgrade_type(conn, move.target_id, move.type),
         :ok <- Histlog.Database.exec(conn, "UPDATE sessions SET cwd_id = ? WHERE cwd_id = ?", [move.target_id, move.id]),
         :ok <- Histlog.Database.exec(conn, "UPDATE commands SET cwd_id = ? WHERE cwd_id = ?", [move.target_id, move.id]),
         :ok <- Histlog.Database.exec(conn, "UPDATE command_paths SET path_id = ? WHERE path_id = ?", [move.target_id, move.id]) do
      Histlog.Database.exec(conn, "DELETE FROM paths WHERE id = ?", [move.id])
    end
  end

  defp rename_path(conn, move) do
    Histlog.Database.exec(conn, "UPDATE paths SET path = ? WHERE id = ?", [move.normalized, move.id])
  end

  defp maybe_upgrade_type(_conn, _target_id, type) when type in [nil, "u"], do: :ok

  defp maybe_upgrade_type(conn, target_id, type) do
    Histlog.Database.exec(
      conn,
      """
      UPDATE paths
      SET type = CASE WHEN type = 'u' THEN ? ELSE type END
      WHERE id = ?
      """,
      [type, target_id]
    )
  end

  defp apply_resolved_path_updates(conn, updates) do
    Enum.reduce_while(updates, :ok, fn update, :ok ->
      case Histlog.Database.exec(conn, "UPDATE command_paths SET resolved_path = ? WHERE id = ?", [
             update.normalized,
             update.id
           ]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp table_column?(conn, table, column) do
    {:ok, rows} = Histlog.Database.query_maps(conn, "PRAGMA table_info(#{table})")
    Enum.any?(rows, &(&1.name == column))
  end

  defp db_path(opts, args) do
    cond do
      db = Keyword.get(opts, :db) ->
        Path.expand(db)

      root = Keyword.get(opts, :root) ->
        root |> Path.expand() |> Path.join("histlog.db")

      args == [] ->
        Path.expand("~/.local/share/histlog/histlog.db")

      true ->
        case args do
          [path] -> Path.expand(path)
          _other -> raise "unexpected arguments: #{inspect(args)}"
        end
    end
  end

  defp load_histlog_modules! do
    repo_root = Path.expand(Path.join(__DIR__, ".."))

    repo_root
    |> Path.join("app/_build/{dev,test,prod}/lib/*/ebin")
    |> Path.wildcard()
    |> Enum.each(&:code.add_patha(String.to_charlist(&1)))
  end

  defp timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.local_time()

    [year, month, day, hour, minute, second]
    |> Enum.zip([4, 2, 2, 2, 2, 2])
    |> Enum.map_join(fn {value, size} ->
      value |> Integer.to_string() |> String.pad_leading(size, "0")
    end)
  end

  defp help do
    """
    Usage: elixir scripts/normalize-db-paths.exs [PATH] [--root PATH] [--db PATH] [--dry-run]

    Normalizes existing histlog.db path rows so paths under the current user's
    home directory use `~` instead of a machine-specific absolute home path.

    The script backs up the database to:

      histlog.db.paths-backup-YYYYMMDDHHMMSS

    This is a standalone maintenance script, not a histlog CLI command.
    """
  end
end

Histlog.NormalizeDbPaths.main()
