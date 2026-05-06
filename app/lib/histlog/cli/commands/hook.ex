defmodule Histlog.CLI.Commands.Hook do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Hook

  @switches Options.common_switches() ++
              [
                shell: :string,
                session: :string,
                command: :string,
                cwd: :string,
                pid: :integer,
                ppid: :integer,
                started_at: :string,
                ended_at: :string,
                host: :string,
                exit_status: :integer,
                session_id: :string
              ]

  @aliases Options.common_aliases()

  def run([action | argv]) do
    with {:ok, opts, []} <- Options.parse(argv, @switches, @aliases),
         {:ok, opts} <- Options.normalize(opts) do
      case dispatch(action, opts) do
        {:ok, session_id} when is_binary(session_id) ->
          IO.puts(session_id)
          :ok

        :ok ->
          :ok

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  def run([]), do: {:error, "missing hook action"}

  defp dispatch("session-start", opts), do: Hook.session_start(opts)
  defp dispatch("preexec", opts), do: Hook.preexec(opts)
  defp dispatch("precmd", opts), do: Hook.precmd(opts)
  defp dispatch("session-end", opts), do: Hook.session_end(opts)
  defp dispatch(action, _opts), do: {:error, {:unknown_hook_action, action}}
end
