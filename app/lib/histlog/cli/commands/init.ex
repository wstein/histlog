defmodule Histlog.CLI.Commands.Init do
  @moduledoc false

  alias Histlog.CLI.Options

  @switches [
    aliases: :boolean,
    binary: :string,
    durability: :string,
    help: :boolean
  ]

  @aliases [h: :help]

  def run(argv) do
    with {:ok, opts, args} <- Options.parse(argv, @switches, @aliases) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        run_init(opts, args)
      end
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp run_init(opts, args) do
    with {:ok, shell} <- Options.one_optional_arg(args),
         {:ok, shell} <- resolve_shell(shell),
         {:ok, script} <- Histlog.Shell.Init.script(shell, opts) do
      IO.write(script)
      :ok
    end
  end

  defp resolve_shell(nil), do: Histlog.Shell.Init.detect()
  defp resolve_shell(shell), do: {:ok, shell}

  defp help do
    """
    Usage: histlog init [zsh|bash|fish] [options]

    Print shell integration code. histlog never edits shell rc files.

    Options:
      -h, --help                    Show this help
          --aliases                 Include convenience aliases
          --binary PATH             Pin an absolute histlog executable path
          --durability MODE         safe, balanced, or fast
    """
  end
end
