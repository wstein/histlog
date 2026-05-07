defmodule Histlog.CLI.Commands.Doctor do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Verifier

  @switches Options.common_switches() ++
              [
                json: :boolean,
                plain: :boolean,
                help: :boolean
              ]

  @aliases Options.common_aliases() ++ [h: :help]

  def run(argv) do
    with {:ok, opts, args} <- Options.parse(argv, @switches, @aliases),
         :ok <- validate_output_opts(opts) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        with {:ok, opts} <- Options.normalize(opts),
             {:ok, shell} <- Options.one_optional_arg(args),
             {:ok, shell} <- resolve_shell(shell) do
          shell
          |> Histlog.Shell.Init.doctor()
          |> add_database_checks(opts)
          |> write(output_format(opts))
        end
      end
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp validate_output_opts(opts) do
    if Keyword.get(opts, :json, false) && Keyword.get(opts, :plain, false) do
      {:error, "choose only one doctor output format"}
    else
      :ok
    end
  end

  defp output_format(opts) do
    if Keyword.get(opts, :json, false), do: :json, else: :plain
  end

  defp add_database_checks(report, opts) do
    verify_result =
      case Verifier.verify(opts) do
        {:ok, verify_report} -> verify_report
        {:error, verify_report} when is_map(verify_report) -> verify_report
        {:error, reason} -> verifier_error_report(reason)
      end

    checks = report["checks"] ++ database_checks(verify_result)

    report
    |> Map.put("checks", checks)
    |> Map.put("database", database_summary(verify_result))
    |> Map.put("database_verification", verify_result)
  end

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
      }
    ]
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

  defp database_status(%{"ok" => true}), do: "ok"
  defp database_status(%{"ok" => false, "error" => "missing"}), do: "missing"
  defp database_status(%{"ok" => false}), do: "failed"
  defp database_status(_check), do: "unknown"

  defp check_status(%{"ok" => true}), do: "ok"
  defp check_status(%{"ok" => false}), do: "failed"
  defp check_status(_check), do: "unknown"

  defp write(report, :json) do
    report
    |> JSON.encode!()
    |> IO.puts()

    :ok
  end

  defp write(report, :plain) do
    IO.puts("shell: #{report["shell"]}")

    Enum.each(report["checks"], fn check ->
      IO.puts("#{check["check"]}: #{check["status"]}")
    end)

    report
    |> get_in(["database", "errors"])
    |> List.wrap()
    |> Enum.each(fn error ->
      IO.puts("database_error: #{error}")
    end)

    :ok
  end

  defp resolve_shell(nil), do: Histlog.Shell.Init.detect()
  defp resolve_shell(shell), do: {:ok, shell}

  defp help do
    """
    Usage: histlog doctor [zsh|bash|fish] [--json|--plain]

    Diagnose shell integration state. Plain text is the default output.
    Use --json for machine-readable diagnostics.

    Options:
      -d, --date YYYY-MM-DD   Check database materialization for one date
      -r, --root PATH         Use a specific histlog data root
    """
  end
end
