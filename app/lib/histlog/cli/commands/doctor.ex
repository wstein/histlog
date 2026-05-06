defmodule Histlog.CLI.Commands.Doctor do
  @moduledoc false

  alias Histlog.CLI.Options

  def run(argv) do
    with {:ok, _opts, args} <- Options.parse(argv, []),
         {:ok, shell} <- Options.one_optional_arg(args),
         {:ok, shell} <- resolve_shell(shell) do
      shell
      |> Histlog.Shell.Init.doctor()
      |> JSON.encode!()
      |> IO.puts()

      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp resolve_shell(nil), do: Histlog.Shell.Init.detect()
  defp resolve_shell(shell), do: {:ok, shell}
end
