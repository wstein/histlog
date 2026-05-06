defmodule Histlog.CLI do
  @moduledoc """
  Command-line interface for histlog v1.
  """

  alias Histlog.Consolidator
  alias Histlog.Query
  alias Histlog.Storage

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
    opts = parse_options(argv)

    case Consolidator.consolidate(opts) do
      {:ok, manifest} ->
        IO.puts(JSON.encode!(manifest))
        :ok

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  def run(["query" | argv]) do
    {filters, opts} = parse_query(argv)

    {:ok, rows} = Query.executions(Keyword.put(opts, :filters, filters))
    Enum.each(rows, &IO.write(JSON.encode!(&1) <> "\n"))
    :ok
  end

  def run(["tail" | argv]) do
    opts = parse_options(argv)
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

  def run(["import", file | argv]) do
    opts = parse_options(argv)
    root = Storage.root(opts)
    date = Keyword.get(opts, :date, Date.utc_today())
    source = Keyword.get(opts, :source, source_name(file))
    session_id = Keyword.get(opts, :session_id, "import-#{source}-#{Date.to_iso8601(date)}")
    import_batch_id = Keyword.get(opts, :import_batch_id, "#{source}-#{Date.to_iso8601(date)}")

    destination =
      Path.join(Storage.imports_dir(root), "#{Date.to_iso8601(date)}-#{source}.ndjson")

    with {:ok, content} <- File.read(file),
         {:ok, events} <- Histlog.Import.from_source(session_id, source, import_batch_id, content),
         output = Histlog.NDJSON.encode!(events),
         :ok <- Storage.atomic_write(destination, output) do
      IO.puts(destination)
      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def run(["hook", action | argv]) do
    opts = parse_options(argv)

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

  def run(_argv) do
    IO.puts("""
    histlog commands:
      histlog consolidate [--root PATH] [--date YYYY-MM-DD]
      histlog query [--root PATH] [--date YYYY-MM-DD] [--command TEXT] [--cwd PATH] [--exit-status N]
      histlog tail [--root PATH] [--date YYYY-MM-DD] [--count N]
      histlog import FILE [--root PATH] [--date YYYY-MM-DD] [--source zsh_history|bash_history|fish_history|ndjson]
      histlog hook session-start|preexec|precmd|session-end
    """)

    :ok
  end

  defp run_hook("session-start", opts), do: Histlog.Hook.session_start(opts)
  defp run_hook("preexec", opts), do: Histlog.Hook.preexec(opts)
  defp run_hook("precmd", opts), do: Histlog.Hook.precmd(opts)
  defp run_hook("session-end", opts), do: Histlog.Hook.session_end(opts)
  defp run_hook(action, _opts), do: {:error, {:unknown_hook_action, action}}

  defp parse_query(argv) do
    opts = parse_options(argv)

    filters =
      opts
      |> Keyword.take([:command, :cwd, :exit_status])
      |> Map.new()

    {filters, Keyword.drop(opts, [:command, :cwd, :exit_status])}
  end

  defp parse_options(argv), do: parse_options(argv, [])

  defp parse_options([], acc), do: Enum.reverse(acc)
  defp parse_options(["--root", root | rest], acc), do: parse_options(rest, [{:root, root} | acc])

  defp parse_options(["--shell", shell | rest], acc),
    do: parse_options(rest, [{:shell, shell} | acc])

  defp parse_options(["--session", session | rest], acc),
    do: parse_options(rest, [{:session, session} | acc])

  defp parse_options(["--command", command | rest], acc),
    do: parse_options(rest, [{:command, command} | acc])

  defp parse_options(["--cwd", cwd | rest], acc), do: parse_options(rest, [{:cwd, cwd} | acc])

  defp parse_options(["--date", date | rest], acc) do
    parse_options(rest, [{:date, Date.from_iso8601!(date)} | acc])
  end

  defp parse_options(["--pid", pid | rest], acc),
    do: parse_options(rest, [{:pid, parse_integer(pid)} | acc])

  defp parse_options(["--ppid", ppid | rest], acc),
    do: parse_options(rest, [{:ppid, parse_integer(ppid)} | acc])

  defp parse_options(["--started-at", started_at | rest], acc),
    do: parse_options(rest, [{:started_at, started_at} | acc])

  defp parse_options(["--ended-at", ended_at | rest], acc),
    do: parse_options(rest, [{:ended_at, ended_at} | acc])

  defp parse_options(["--host", host | rest], acc), do: parse_options(rest, [{:host, host} | acc])

  defp parse_options(["--exit-status", status | rest], acc) do
    parse_options(rest, [{:exit_status, parse_integer(status)} | acc])
  end

  defp parse_options(["--count", count | rest], acc) do
    parse_options(rest, [{:count, String.to_integer(count)} | acc])
  end

  defp parse_options(["--source", source | rest], acc),
    do: parse_options(rest, [{:source, source} | acc])

  defp parse_options(["--session-id", session_id | rest], acc),
    do: parse_options(rest, [{:session_id, session_id} | acc])

  defp parse_options(["--import-batch-id", import_batch_id | rest], acc),
    do: parse_options(rest, [{:import_batch_id, import_batch_id} | acc])

  defp parse_options([unknown | _rest], _acc),
    do: raise(ArgumentError, "unknown option #{unknown}")

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(value), do: String.to_integer(value)

  defp source_name(file) do
    file
    |> Path.basename()
    |> String.replace(~r/[^A-Za-z0-9_.-]/, "_")
  end
end
