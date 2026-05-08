#!/usr/bin/env elixir

defmodule Histlog.FlattenSessionLayout do
  @moduledoc false

  @states ~w(live closed quarantine)
  @date_prefix ~r/^session-\d{4}-\d{2}-\d{2}-/

  def main(argv \\ System.argv()) do
    {opts, args, invalid} =
      OptionParser.parse(argv,
        strict: [
          root: :string,
          dry_run: :boolean,
          help: :boolean
        ],
        aliases: [
          r: :root,
          h: :help
        ]
      )

    cond do
      opts[:help] ->
        IO.write(help())

      invalid != [] ->
        fail!("invalid options #{inspect(invalid)}")

      args != [] ->
        fail!("unexpected arguments #{inspect(args)}")

      true ->
        root = Path.expand(opts[:root] || "~/.local/share/histlog")
        dry_run? = Keyword.get(opts, :dry_run, false)
        report = flatten!(root, dry_run?)
        IO.puts(JSON.encode!(report))
    end
  rescue
    exception ->
      fail!(Exception.message(exception))
  end

  defp flatten!(root, dry_run?) do
    moves =
      root
      |> planned_moves()
      |> Enum.sort_by(&{&1.state, &1.date, &1.source})

    collisions =
      Enum.filter(moves, fn move ->
        File.exists?(move.destination) and !same_file?(move.source, move.destination)
      end)

    if collisions != [] do
      raise """
      refusing to overwrite existing flat session files:
      #{Enum.map_join(collisions, "\n", &"#{&1.source} -> #{&1.destination}")}
      """
    end

    unless dry_run? do
      Enum.each(moves, &move_session!/1)
      remove_empty_legacy_date_dirs!(root)
    end

    %{
      "root" => root,
      "dry_run" => dry_run?,
      "moves" => Enum.map(moves, &move_report/1),
      "moves_count" => length(moves)
    }
  end

  defp planned_moves(root) do
    Enum.flat_map(@states, fn state ->
      pattern = Path.join([root, "sessions", state, "*", "*.ndjson"])

      pattern
      |> Path.wildcard()
      |> Enum.flat_map(&plan_move(root, state, &1))
    end)
  end

  defp plan_move(root, state, source) do
    date = source |> Path.dirname() |> Path.basename()

    case Date.from_iso8601(date) do
      {:ok, _date} ->
        basename = Path.basename(source)
        destination = Path.join([root, "sessions", state, flat_basename(date, basename)])

        if source == destination do
          []
        else
          [
            %{
              state: state,
              date: date,
              source: source,
              destination: destination
            }
          ]
        end

      {:error, _reason} ->
        []
    end
  end

  defp flat_basename(date, basename) do
    if Regex.match?(@date_prefix, basename) do
      basename
    else
      add_date_to_basename(date, basename)
    end
  end

  defp add_date_to_basename(date, "session-" <> rest), do: "session-#{date}-#{rest}"
  defp add_date_to_basename(date, basename), do: "session-#{date}-#{basename}"

  defp move_session!(move) do
    File.mkdir_p!(Path.dirname(move.destination))

    cond do
      File.exists?(move.destination) and same_file?(move.source, move.destination) ->
        File.rm!(move.source)

      true ->
        File.rename!(move.source, move.destination)
    end
  end

  defp same_file?(left, right) do
    File.exists?(left) and File.exists?(right) and File.read!(left) == File.read!(right)
  end

  defp remove_empty_legacy_date_dirs!(root) do
    Enum.each(@states, fn state ->
      root
      |> Path.join("sessions/#{state}/*")
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)
      |> Enum.sort_by(&String.length/1, :desc)
      |> Enum.each(fn dir ->
        case File.rmdir(dir) do
          :ok -> :ok
          {:error, :enoent} -> :ok
          {:error, :eexist} -> :ok
          {:error, :enotempty} -> :ok
          {:error, _reason} -> :ok
        end
      end)
    end)
  end

  defp move_report(move) do
    %{
      "state" => move.state,
      "date" => move.date,
      "source" => move.source,
      "destination" => move.destination
    }
  end

  defp fail!(message) do
    IO.puts(:stderr, "flatten-session-layout: #{message}")
    System.halt(1)
  end

  defp help do
    """
    Usage: elixir scripts/flatten-session-layout.exs [--root PATH] [--dry-run]

    Moves legacy dated session files:

      sessions/live/YYYY-MM-DD/session-*.ndjson
      sessions/closed/YYYY-MM-DD/session-*.ndjson
      sessions/quarantine/YYYY-MM-DD/session-*.ndjson

    into the flat v1 layout:

      sessions/live/session-YYYY-MM-DD-*.ndjson
      sessions/closed/session-YYYY-MM-DD-*.ndjson
      sessions/quarantine/session-YYYY-MM-DD-*.ndjson

    This script is a standalone maintenance tool, not a histlog CLI command.
    """
  end
end

Histlog.FlattenSessionLayout.main()
