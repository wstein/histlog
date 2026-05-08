defmodule Histlog.CLI.Commands.Sync do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Consolidator

  @switches Options.common_switches() ++ [json: :boolean, help: :boolean]
  @aliases Options.common_aliases() ++ [h: :help]

  def run(argv) do
    with {:ok, opts, []} <- Options.parse(argv, @switches, @aliases) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        run_sync(opts)
      end
    end
  end

  defp run_sync(opts) do
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
    IO.puts("#{color_label("date")}: #{report["date"]}")
    IO.puts("#{color_label("dates")}: #{color_count(length(report["dates"] || []))}")
    IO.puts("#{color_label("database")}: #{report["database_path"]}")
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

  defp help do
    """
    Usage: histlog sync [options]

    Materialize closed shell sessions into histlog.db for querying.
    Without --date, all closed session dates are materialized.

    Options:
      -h, --help              Show this help
      -d, --date YYYY-MM-DD   Sync one date
      -r, --root PATH         Use a specific histlog data root
          --json              Output the full JSON report
    """
  end
end
