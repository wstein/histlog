defmodule Histlog.CLI.Commands.Info do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Storage

  @env_keys ~w(HISTLOG_ROOT HISTLOG_ACTIVE HISTLOG_SESSION_ID HISTLOG_SHELL HISTLOG_DURABILITY HISTLOG_BIN SHELL)

  @switches [
    root: :string,
    json: :boolean,
    plain: :boolean,
    help: :boolean
  ]

  @aliases [
    r: :root,
    h: :help
  ]

  def run(argv) do
    with {:ok, opts, args} <- Options.parse(argv, @switches, @aliases),
         :ok <- validate_output_opts(opts) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        with {:ok, shell_arg} <- Options.one_optional_arg(args) do
          opts
          |> report(shell_arg)
          |> write(output_format(opts))
        end
      end
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp report(opts, shell_arg) do
    env = System.get_env()
    root = Storage.root(opts)

    %{
      "version" => version(),
      "command" => %{
        "histlog_bin" => env["HISTLOG_BIN"],
        "path_histlog" => System.find_executable("histlog")
      },
      "paths" => %{
        "data_root" => root,
        "database" => Storage.database_path(root)
      },
      "shell" => %{
        "argument" => shell_arg,
        "detected" => detected_shell(),
        "supported" => Histlog.Shell.Init.supported_shells(),
        "future" => Histlog.Shell.Init.future_shells()
      },
      "env" => Map.new(@env_keys, fn key -> {key, env[key]} end),
      "runtime" => %{
        "elixir" => System.version(),
        "otp" => otp_release()
      }
    }
  end

  defp validate_output_opts(opts) do
    if Keyword.get(opts, :json, false) && Keyword.get(opts, :plain, false) do
      {:error, "choose only one info output format"}
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
    IO.puts("version: #{report["version"]}")
    IO.puts("path_histlog: #{display(report["command"]["path_histlog"])}")
    IO.puts("histlog_bin: #{display(report["command"]["histlog_bin"])}")
    IO.puts("data_root: #{report["paths"]["data_root"]}")
    IO.puts("database: #{report["paths"]["database"]}")
    IO.puts("shell_argument: #{display(report["shell"]["argument"])}")
    IO.puts("shell_detected: #{display(report["shell"]["detected"])}")
    IO.puts("supported_shells: #{Enum.join(report["shell"]["supported"], ", ")}")
    IO.puts("elixir: #{report["runtime"]["elixir"]}")
    IO.puts("otp: #{report["runtime"]["otp"]}")

    Enum.each(@env_keys, fn key ->
      IO.puts("env.#{key}: #{display(report["env"][key])}")
    end)

    :ok
  end

  defp detected_shell do
    case Histlog.Shell.Init.detect() do
      {:ok, shell} -> shell
      {:error, _reason} -> nil
    end
  end

  defp version do
    with nil <- Application.spec(:histlog, :vsn),
         :ok <- Application.load(:histlog) do
      Application.spec(:histlog, :vsn)
    end
    |> case do
      nil -> "unknown"
      version when is_list(version) -> List.to_string(version)
      version when is_binary(version) -> version
    end
  end

  defp otp_release, do: :erlang.system_info(:otp_release) |> List.to_string()

  defp display(nil), do: "unset"
  defp display(""), do: "unset"
  defp display(value), do: to_string(value)

  defp help do
    """
    Usage: histlog info [shell] [--json|--plain]

    Show runtime and environment information without diagnosing it.
    Use histlog doctor to diagnose setup and database health.

    Options:
      -r, --root PATH         Show paths for a specific histlog data root
      --json                  Output machine-readable information
      --plain                 Output plain text information
      -h, --help              Show this help
    """
  end
end
