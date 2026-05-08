defmodule Histlog.CLI.Commands.Health do
  @moduledoc false

  alias Histlog.Verifier
  alias Histlog.Database.Maintenance

  def build(shell, opts) do
    shell
    |> Histlog.Shell.Init.doctor()
    |> add_database_checks(opts)
  end

  def write_doctor(report, :json) do
    report
    |> JSON.encode!()
    |> IO.puts()

    :ok
  end

  def write_doctor(report, :plain) do
    failing_checks =
      report["checks"]
      |> Enum.reject(fn check -> check["status"] in ["ok", "active", "present"] end)

    if failing_checks == [] do
      IO.puts("diagnosis: #{color_status("ok")}")
    else
      IO.puts("diagnosis: #{color_status("attention")}")
    end

    IO.puts("#{color_label("detected_shell")}: #{report["shell"]}")

    Enum.each(report["checks"], fn check ->
      IO.puts("#{color_label(check["check"])}: #{color_status(check["status"])}")
    end)

    report
    |> get_in(["database", "errors"])
    |> List.wrap()
    |> Enum.each(fn error ->
      IO.puts("#{color_label("database_error")}: #{color(error, "38;5;203")}")
    end)

    verification = report["database_verification"] || %{}
    maintenance = report["database_maintenance"] || %{}
    checks = verification["checks"] || %{}
    schema = checks["schema"] || %{}
    counts = checks["counts"] || %{}
    tables = checks["tables"] || %{}
    maintenance_checks = maintenance["checks"] || %{}
    integrity = maintenance_checks["integrity"] || %{}
    orphans = maintenance_checks["orphans"] || %{}

    IO.puts(
      "#{color_label("database_path")}: #{report |> get_in(["database", "path"]) |> inspect_nil()}"
    )

    IO.puts(
      "#{color_label("database_date")}: #{report |> get_in(["database", "date"]) |> inspect_nil()}"
    )

    IO.puts("#{color_label("schema_expected")}: #{inspect_nil(schema["expected"])}")
    IO.puts("#{color_label("schema_actual")}: #{inspect_nil(schema["actual"])}")

    if counts != %{} do
      IO.puts(
        "#{color_label("counts_detail")}: processed_sessions=#{inspect(counts["processed_sessions"])} sessions=#{inspect(counts["sessions"])} processed_command_rows=#{inspect(counts["processed_command_rows"])} commands=#{inspect(counts["commands"])}"
      )
    end

    if tables != %{} do
      missing =
        tables
        |> Enum.reject(fn {_name, check} -> check["ok"] end)
        |> Enum.map(fn {name, _check} -> name end)
        |> Enum.sort()

      if missing == [] do
        IO.puts("#{color_label("tables_detail")}: #{color_status("ok")}")
      else
        IO.puts(
          "#{color_label("tables_detail")}: #{color_status("missing")} #{Enum.join(missing, ", ")}"
        )
      end
    end

    if integrity != %{} do
      IO.puts("#{color_label("sqlite_integrity")}: #{color_status(check_status(integrity))}")
    end

    if orphans != %{} do
      orphan_counts = orphans["counts"] || %{}

      IO.puts(
        "#{color_label("orphan_checks")}: #{color_status(check_status(orphans))} #{format_counts(orphan_counts)}"
      )
    end

    Enum.each(failing_checks, fn check ->
      IO.puts("#{color_label("recommendation")}: #{color(recommendation(check), "38;5;220")}")
    end)

    :ok
  end

  defp add_database_checks(report, opts) do
    verify_result =
      case Verifier.verify(opts) do
        {:ok, verify_report} -> verify_report
        {:error, verify_report} when is_map(verify_report) -> verify_report
        {:error, reason} -> verifier_error_report(reason)
      end

    maintenance = maintenance_report(opts)
    checks = report["checks"] ++ database_checks(verify_result, maintenance)

    report
    |> Map.put("checks", checks)
    |> Map.put("ok", Enum.all?(checks, &healthy_check?/1))
    |> Map.put("database", database_summary(verify_result))
    |> Map.put("database_verification", verify_result)
    |> Map.put("database_maintenance", maintenance)
  end

  defp healthy_check?(%{"status" => status}), do: status in ["ok", "active", "present"]

  defp database_checks(report) do
    checks = report["checks"] || %{}

    [
      %{
        "check" => "database",
        "status" => database_status(checks["database"])
      },
      %{
        "check" => "schema",
        "status" => check_status(checks["schema"])
      },
      %{
        "check" => "materialization_counts",
        "status" => check_status(checks["counts"])
      },
      %{
        "check" => "sqlite_integrity",
        "status" => "pending"
      },
      %{
        "check" => "orphan_checks",
        "status" => "pending"
      }
    ]
  end

  defp database_checks(report, maintenance) do
    report
    |> database_checks()
    |> Enum.map(fn
      %{"check" => "sqlite_integrity"} = check ->
        %{check | "status" => check_status(get_in(maintenance, ["checks", "integrity"]))}

      %{"check" => "orphan_checks"} = check ->
        %{check | "status" => check_status(get_in(maintenance, ["checks", "orphans"]))}

      check ->
        check
    end)
  end

  defp database_summary(report) do
    %{
      "ok" => report["ok"],
      "date" => report["date"],
      "path" => report["database_path"],
      "errors" => report["errors"] || []
    }
  end

  defp verifier_error_report(reason) do
    %{
      "ok" => false,
      "date" => nil,
      "database_path" => nil,
      "errors" => [inspect(reason)],
      "checks" => %{}
    }
  end

  defp maintenance_report(opts) do
    case Maintenance.diagnose(opts) do
      {:ok, report} -> report
      {:error, report} when is_map(report) -> report
    end
  end

  defp format_counts(counts) when counts == %{}, do: ""

  defp format_counts(counts) do
    counts
    |> Enum.sort_by(fn {name, _count} -> name end)
    |> Enum.map(fn {name, count} -> "#{name}=#{inspect(count)}" end)
    |> Enum.join(" ")
  end

  defp database_status(%{"ok" => true}), do: "ok"
  defp database_status(%{"ok" => false, "error" => "missing"}), do: "missing"
  defp database_status(%{"ok" => false}), do: "failed"
  defp database_status(_check), do: "unknown"

  defp check_status(%{"ok" => true}), do: "ok"
  defp check_status(%{"ok" => false}), do: "failed"
  defp check_status(_check), do: "unknown"

  defp inspect_nil(nil), do: "nil"
  defp inspect_nil(value), do: to_string(value)

  defp color_status(status) when status in ["ok", "active", "present"],
    do: color(status, "38;5;84")

  defp color_status("attention"), do: color("attention", "38;5;220")
  defp color_status("missing"), do: color("missing", "38;5;220")
  defp color_status("inactive"), do: color("inactive", "38;5;220")
  defp color_status("failed"), do: color("failed", "38;5;203")
  defp color_status("unsupported"), do: color("unsupported", "38;5;203")
  defp color_status(status), do: color(to_string(status), "38;5;8")

  defp color_label(label), do: color(label, "38;5;14")

  defp color(text, code), do: "\e[#{code}m#{text}\e[0m"

  defp recommendation(%{"check" => "shell", "status" => "unsupported"}),
    do:
      "run `histlog init zsh`, `histlog init bash`, or `histlog init fish` from a supported shell"

  defp recommendation(%{"check" => "histlog_active"}),
    do: "source the integration snippet for your shell, for example `histlog init fish | source`"

  defp recommendation(%{"check" => "session_id"}),
    do: "restart or re-source the shell integration so it can register a histlog session"

  defp recommendation(%{"check" => "database", "status" => "missing"}),
    do: "run `histlog sync --date YYYY-MM-DD` or import history to create histlog.db"

  defp recommendation(%{"check" => "database"}),
    do: "run `histlog rebuild --date YYYY-MM-DD` after checking the database path"

  defp recommendation(%{"check" => "schema"}),
    do: "run `histlog rebuild --date YYYY-MM-DD` to rebuild the derived database projection"

  defp recommendation(%{"check" => "materialization_counts"}),
    do: "run `histlog rebuild --date YYYY-MM-DD` to refresh database checkpoints"

  defp recommendation(%{"check" => "sqlite_integrity"}),
    do: "rebuild the derived projection after backing up suspicious database files"

  defp recommendation(%{"check" => "orphan_checks"}),
    do: "run `histlog rebuild --date YYYY-MM-DD` to refresh database relationships"

  defp recommendation(check), do: "inspect #{check["check"]}"
end
