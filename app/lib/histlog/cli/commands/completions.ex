defmodule Histlog.CLI.Commands.Completions do
  @moduledoc false

  alias Histlog.CLI.Options

  def run(argv) do
    with {:ok, _opts, args} <- Options.parse(argv, []),
         {:ok, shell} <- Options.one_optional_arg(args),
         {:ok, shell} <- resolve_shell(shell),
         {:ok, script} <- Histlog.Shell.Init.completions(shell) do
      IO.write(script)
      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp resolve_shell(nil), do: Histlog.Shell.Init.detect()
  defp resolve_shell(shell), do: {:ok, shell}
end
