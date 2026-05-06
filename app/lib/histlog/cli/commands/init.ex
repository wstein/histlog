defmodule Histlog.CLI.Commands.Init do
  @moduledoc false

  alias Histlog.CLI.Options

  @switches [
    aliases: :boolean,
    binary: :string
  ]

  def run(argv) do
    with {:ok, opts, args} <- Options.parse(argv, @switches),
         {:ok, shell} <- Options.one_optional_arg(args),
         {:ok, shell} <- resolve_shell(shell),
         {:ok, script} <- Histlog.Shell.Init.script(shell, opts) do
      IO.write(script)
      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp resolve_shell(nil), do: Histlog.Shell.Init.detect()
  defp resolve_shell(shell), do: {:ok, shell}
end
