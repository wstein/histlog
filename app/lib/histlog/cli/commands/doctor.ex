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
          |> write(Keyword.get(opts, :plain, false))
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

  defp write(report, false) do
    report
    |> JSON.encode!()
    |> IO.puts()

    :ok
  end

  defp write(report, true) do
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

    Diagnose shell integration state. JSON is the default output.
    """
  end
end
