defmodule Histlog.CLI.Commands.Doctor do
  @moduledoc false

  alias Histlog.CLI.Options

  @switches [
    json: :boolean,
    plain: :boolean,
    help: :boolean
  ]

  @aliases [h: :help]

  def run(argv) do
    with {:ok, opts, args} <- Options.parse(argv, @switches, @aliases),
         :ok <- validate_output_opts(opts) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        with {:ok, shell} <- Options.one_optional_arg(args),
             {:ok, shell} <- resolve_shell(shell) do
          shell
          |> Histlog.Shell.Init.doctor()
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

    :ok
  end

  defp resolve_shell(nil), do: Histlog.Shell.Init.detect()
  defp resolve_shell(shell), do: {:ok, shell}

  defp help do
    """
    Usage: histlog doctor [zsh|bash|fish] [--json|--plain]

    Diagnose shell integration state. Plain text is the default output.
    Use --json for machine-readable diagnostics.
    """
  end
end
