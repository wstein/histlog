defmodule Histlog.CLI.Commands.Doctor do
  @moduledoc false

  alias Histlog.CLI.Commands.Health
  alias Histlog.CLI.Options

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
          |> Health.build(opts)
          |> Health.write_doctor(output_format(opts))
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

  defp resolve_shell(nil), do: Histlog.Shell.Init.detect()
  defp resolve_shell(shell), do: {:ok, shell}

  defp help do
    """
    Usage: histlog doctor [zsh|bash|fish] [--json|--plain]

    Diagnose shell integration and database health. Plain text is the default output.
    Use --json for machine-readable diagnostics.

    Options:
      -d, --date YYYY-MM-DD   Check database materialization for one date
      -r, --root PATH         Use a specific histlog data root
    """
  end
end
