defmodule Histlog.CLI.Commands.Db do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Consolidator

  @switches Options.common_switches() ++ [json: :boolean, help: :boolean]
  @aliases Options.common_aliases() ++ [h: :help]

  def run([]), do: write_help()
  def run(["--help"]), do: write_help()
  def run(["-h"]), do: write_help()

  def run(["rebuild" | argv]), do: rebuild(argv)
  def run([command | _argv]), do: {:error, "unknown db command #{inspect(command)}"}

  defp rebuild(argv) do
    with {:ok, opts, []} <- Options.parse(argv, @switches, @aliases) do
      if Keyword.get(opts, :help, false) do
        write_rebuild_help()
      else
        run_rebuild(opts)
      end
    end
  end

  defp run_rebuild(opts) do
    opts = Keyword.put(opts, :rebuild, true)

    with {:ok, opts} <- Options.normalize(opts) do
      case Consolidator.consolidate(opts) do
        {:ok, report} -> write_report(report, output_format(opts))
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  defp output_format(opts) do
    if Keyword.get(opts, :json, false), do: :json, else: :plain
  end

  defp write_report(report, :json) do
    IO.puts(JSON.encode!(report))
    :ok
  end

  defp write_report(report, :plain) do
    IO.puts("#{color_label("database")}: #{report["database_path"]}")
    IO.puts("#{color_label("date")}: #{report["date"]}")
    IO.puts("#{color_label("dates")}: #{color_count(length(report["dates"] || []))}")
    IO.puts("#{color_label("schema")}: #{report["schema_version"]}")

    IO.puts(
      "#{color_label("sessions")}: #{color_count(length(report["sessions_processed"] || []))}"
    )

    IO.puts("#{color_label("events")}: #{color_count(report["records_written"] || 0)}")
    IO.puts("#{color_label("commands")}: #{color_count(report["exec_records_written"] || 0)}")
    IO.puts("#{color_label("rebuilt")}: #{color_bool(report["rebuilt"])}")
    IO.puts("#{color_label("schema_reset")}: #{color_bool(report["schema_reset"])}")

    case report["quarantined_sessions"] || [] do
      [] ->
        IO.puts("#{color_label("quarantine")}: #{color_status("ok")}")

      quarantined ->
        IO.puts("#{color_label("quarantine")}: #{color_status("attention")}")

        Enum.each(quarantined, fn entry ->
          IO.puts("  #{entry["session"]}: #{entry["reason"]}")
        end)
    end

    :ok
  end

  defp color_count(0), do: color("0", "38;5;8")
  defp color_count(value), do: color(to_string(value), "38;5;80")

  defp color_bool(true), do: color("true", "38;5;220")
  defp color_bool(false), do: color("false", "38;5;8")

  defp color_status("ok"), do: color("ok", "38;5;84")
  defp color_status("attention"), do: color("attention", "38;5;220")

  defp color_label(label), do: color(label, "38;5;14")
  defp color(text, code), do: "\e[#{code}m#{text}\e[0m"

  defp write_help do
    IO.write(help())
    :ok
  end

  defp write_rebuild_help do
    IO.write(rebuild_help())
    :ok
  end

  defp help do
    """
    Usage: histlog db <command> [options]

    Database maintenance commands for the derived histlog.db projection.

    Commands:
      rebuild     Rebuild derived database rows from canonical session files

    Run `histlog db rebuild --help` for rebuild options.
    """
  end

  defp rebuild_help do
    """
    Usage: histlog db rebuild [options]

    Rebuild derived database rows from canonical closed session files.
    Without --date, all closed session dates are rebuilt.

    Options:
      -h, --help              Show this help
      -d, --date YYYY-MM-DD   Rebuild one date
      -r, --root PATH         Use a specific histlog data root
          --json              Output the full JSON report
    """
  end
end
