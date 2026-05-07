defmodule Histlog.CLI.Commands.Verify do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Verifier

  @switches Options.common_switches() ++ [help: :boolean, json: :boolean]
  @aliases Options.common_aliases() ++ [h: :help]

  def run(argv) do
    with {:ok, opts, []} <- Options.parse(argv, @switches, @aliases) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        run_verify(opts)
      end
    end
  end

  defp run_verify(opts) do
    with {:ok, opts} <- Options.normalize(opts) do
      case Verifier.verify(opts) do
        {:ok, report} ->
          write_report(report, Keyword.get(opts, :json, false))
          :ok

        {:error, report} when is_map(report) ->
          write_report(report, Keyword.get(opts, :json, false))
          {:error, "verification failed"}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  defp write_report(report, true) do
    IO.puts(JSON.encode!(report))
  end

  defp write_report(report, false) do
    status = if report["ok"], do: "ok", else: "failed"
    checks = report["checks"] || %{}
    database = checks["database"] || %{}
    schema = checks["schema"] || %{}
    counts = checks["counts"] || %{}
    tables = checks["tables"] || %{}

    IO.puts("status: #{status}")
    IO.puts("date: #{report["date"]}")
    IO.puts("database: #{report["database_path"] || database["path"]}")

    IO.puts(
      "schema: #{check_status(schema)} expected=#{schema["expected"]} actual=#{schema["actual"]}"
    )

    if map_size(tables) > 0 do
      missing =
        tables
        |> Enum.reject(fn {_name, check} -> check["ok"] end)
        |> Enum.map(fn {name, _check} -> name end)
        |> Enum.sort()

      if missing == [] do
        IO.puts("tables: ok")
      else
        IO.puts("tables: missing #{Enum.join(missing, ", ")}")
      end
    end

    if counts != %{} do
      IO.puts(
        "counts: #{check_status(counts)} processed_sessions=#{inspect(counts["processed_sessions"])} sessions=#{inspect(counts["sessions"])} processed_command_rows=#{inspect(counts["processed_command_rows"])} commands=#{inspect(counts["commands"])}"
      )
    end

    Enum.each(report["errors"] || [], fn error ->
      IO.puts("error: #{error}")
    end)
  end

  defp check_status(%{"ok" => true}), do: "ok"
  defp check_status(%{"ok" => false}), do: "failed"
  defp check_status(_check), do: "unknown"

  defp help do
    """
    Usage: histlog verify [options] [--json]

    Verify database schema and consolidation checkpoints.

    Options:
      -h, --help              Show this help
      -d, --date YYYY-MM-DD   Verify one date
      -r, --root PATH         Use a specific histlog data root
      --json                  Output full verification report as JSON
    """
  end
end
