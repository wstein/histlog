defmodule Histlog.CLI do
  @moduledoc """
  Command-line interface for histlog v1.
  """

  alias Histlog.Consolidator
  alias Histlog.Query
  alias Histlog.Storage
  alias Histlog.Verifier

  @common_switches [
    root: :string,
    date: :string
  ]

  @query_switches @common_switches ++
                    [
                      command: :string,
                      cwd: :string,
                      exit_status: :integer
                    ]

  @tail_switches @common_switches ++ [count: :integer]

  @import_switches @common_switches ++
                     [
                       source: :string,
                       session_id: :string,
                       import_batch_id: :string
                     ]

  @hook_switches @common_switches ++
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

  @init_switches [
    aliases: :boolean
  ]

  @doc false
  def main(argv) do
    case run(argv) do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "histlog: #{reason}")
        System.halt(1)
    end
  end

  def run(["consolidate" | argv]) do
    with {:ok, opts, []} <- parse_options(argv, @common_switches),
         {:ok, opts} <- normalize_options(opts) do
      case Consolidator.consolidate(opts) do
        {:ok, manifest} ->
          IO.puts(JSON.encode!(manifest))
          :ok

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  def run(["query" | argv]) do
    with {:ok, opts, []} <- parse_options(argv, @query_switches),
         {:ok, opts} <- normalize_options(opts) do
      {filters, opts} = query_options(opts)

      {:ok, rows} = Query.executions(Keyword.put(opts, :filters, filters))
      Enum.each(rows, &IO.write(JSON.encode!(&1) <> "\n"))
      :ok
    end
  end

  def run(["verify" | argv]) do
    with {:ok, opts, []} <- parse_options(argv, @common_switches),
         {:ok, opts} <- normalize_options(opts) do
      case Verifier.verify(opts) do
        {:ok, report} ->
          IO.puts(JSON.encode!(report))
          :ok

        {:error, report} when is_map(report) ->
          IO.puts(JSON.encode!(report))
          {:error, "verification failed"}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  def run(["tail" | argv]) do
    with {:ok, opts, []} <- parse_options(argv, @tail_switches),
         {:ok, opts} <- normalize_options(opts) do
      root = Storage.root(opts)
      date = Keyword.get(opts, :date, Date.utc_today())
      count = Keyword.get(opts, :count, 10)
      path = Storage.daily_events_path(root, date)

      if File.exists?(path) do
        path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.take(-count)
        |> Enum.each(&IO.puts/1)
      end

      :ok
    end
  end

  def run(["import", file | argv]) do
    with {:ok, opts, []} <- parse_options(argv, @import_switches),
         {:ok, opts} <- normalize_options(opts) do
      root = Storage.root(opts)
      date = Keyword.get(opts, :date, Date.utc_today())
      source = Keyword.get(opts, :source, source_name(file))
      session_id = Keyword.get(opts, :session_id, "import-#{source}-#{Date.to_iso8601(date)}")
      import_batch_id = Keyword.get(opts, :import_batch_id, "#{source}-#{Date.to_iso8601(date)}")

      destination =
        Path.join(Storage.imports_dir(root), "#{Date.to_iso8601(date)}-#{source}.ndjson")

      with {:ok, content} <- File.read(file),
           {:ok, events} <-
             Histlog.Import.from_source(session_id, source, import_batch_id, content),
           output = Histlog.NDJSON.encode!(events),
           :ok <- Storage.atomic_write(destination, output) do
        IO.puts(destination)
        :ok
      else
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  def run(["import" | _argv]), do: {:error, "missing import file"}

  def run(["hook", action | argv]) do
    with {:ok, opts, []} <- parse_options(argv, @hook_switches),
         {:ok, opts} <- normalize_options(opts) do
      case run_hook(action, opts) do
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

  def run(["hook" | _argv]), do: {:error, "missing hook action"}

  def run(["init" | argv]) do
    with {:ok, opts, args} <- parse_options(argv, @init_switches),
         {:ok, shell} <- one_optional_arg(args),
         {:ok, shell} <- resolve_shell(shell),
         {:ok, script} <- Histlog.Shell.Init.script(shell, opts) do
      IO.write(script)
      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def run(["completions" | argv]) do
    with {:ok, _opts, args} <- parse_options(argv, []),
         {:ok, shell} <- one_optional_arg(args),
         {:ok, shell} <- resolve_shell(shell),
         {:ok, script} <- Histlog.Shell.Init.completions(shell) do
      IO.write(script)
      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def run(["doctor" | argv]) do
    with {:ok, _opts, args} <- parse_options(argv, []),
         {:ok, shell} <- one_optional_arg(args),
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

  def run(_argv) do
    IO.puts("""
    histlog commands:
      histlog consolidate [--root PATH] [--date YYYY-MM-DD]
      histlog verify [--root PATH] [--date YYYY-MM-DD]
      histlog query [--root PATH] [--date YYYY-MM-DD] [--command TEXT] [--cwd PATH] [--exit-status N]
      histlog tail [--root PATH] [--date YYYY-MM-DD] [--count N]
      histlog import FILE [--root PATH] [--date YYYY-MM-DD] [--source zsh_history|bash_history|fish_history|ndjson]
      histlog hook session-start|preexec|precmd|session-end
      histlog init [zsh|bash|fish] [--aliases]
      histlog completions [zsh|bash|fish]
      histlog doctor [zsh|bash|fish]
    """)

    :ok
  end

  defp run_hook("session-start", opts), do: Histlog.Hook.session_start(opts)
  defp run_hook("preexec", opts), do: Histlog.Hook.preexec(opts)
  defp run_hook("precmd", opts), do: Histlog.Hook.precmd(opts)
  defp run_hook("session-end", opts), do: Histlog.Hook.session_end(opts)
  defp run_hook(action, _opts), do: {:error, {:unknown_hook_action, action}}

  defp resolve_shell(nil), do: Histlog.Shell.Init.detect()
  defp resolve_shell(shell), do: {:ok, shell}

  defp query_options(opts) do
    filters =
      opts
      |> Keyword.take([:command, :cwd, :exit_status])
      |> Map.new()

    {filters, Keyword.drop(opts, [:command, :cwd, :exit_status])}
  end

  defp parse_options(argv, switches) do
    case OptionParser.parse(argv, strict: switches) do
      {opts, args, []} -> {:ok, opts, args}
      {_opts, _args, invalid} -> {:error, "invalid options #{inspect(invalid)}"}
    end
  end

  defp normalize_options(opts) do
    {:ok,
     Enum.map(opts, fn
       {:date, date} -> {:date, parse_date(date)}
       option -> option
     end)}
  rescue
    exception in ArgumentError -> {:error, Exception.message(exception)}
  end

  defp one_optional_arg([]), do: {:ok, nil}
  defp one_optional_arg([arg]), do: {:ok, arg}
  defp one_optional_arg(args), do: {:error, "unexpected arguments #{inspect(args)}"}

  defp parse_date(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed} -> parsed
      {:error, reason} -> raise ArgumentError, "invalid date #{inspect(date)}: #{reason}"
    end
  end

  defp source_name(file) do
    file
    |> Path.basename()
    |> String.replace(~r/[^A-Za-z0-9_.-]/, "_")
  end
end
