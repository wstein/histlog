defmodule Histlog.CLI do
  @moduledoc """
  Command-line interface for histlog v1.
  """

  alias Histlog.CLI.Commands

  @doc false
  def main(argv) do
    case run(argv) do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "histlog: #{format_error(reason)}")
        System.halt(1)
    end
  end

  def run(["consolidate" | argv]), do: Commands.Consolidate.run(argv)
  def run(["verify" | argv]), do: Commands.Verify.run(argv)
  def run(["query" | argv]), do: Commands.Query.run(argv)
  def run(["paths" | argv]), do: Commands.Paths.run(argv)
  def run(["sessions" | argv]), do: Commands.Sessions.run(argv)
  def run(["import" | argv]), do: Commands.Import.run(argv)
  def run(["hook" | argv]), do: Commands.Hook.run(argv)
  def run(["init" | argv]), do: Commands.Init.run(argv)
  def run(["doctor" | argv]), do: Commands.Doctor.run(argv)
  def run(["help" | argv]), do: Commands.Help.run(argv)
  def run(["--help" | _argv]), do: Commands.Help.run([])
  def run(["-h" | _argv]), do: Commands.Help.run([])
  def run(["--help-all" | _argv]), do: Commands.Help.run(["--all"])
  def run([]), do: Commands.Help.run([])
  def run([unknown | _argv]), do: {:error, {:unknown_command, unknown}}

  defp format_error({:unknown_command, command}), do: "unknown command #{inspect(command)}"
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
