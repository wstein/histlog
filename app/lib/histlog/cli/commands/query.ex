defmodule Histlog.CLI.Commands.Query do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Query
  alias Histlog.Query.Duration
  alias Histlog.Query.Filter
  alias Histlog.Query.Render

  @switches Options.common_switches() ++
              [
                regex: :string,
                delete: :boolean,
                force_delete: :boolean,
                asc: :boolean,
                desc: :boolean,
                session: :string,
                fuzzy: :boolean,
                command: :string,
                dir: :string,
                failed: :boolean,
                success: :boolean,
                exit: :integer,
                time: :string,
                since: :string,
                before: :string,
                today: :boolean,
                yesterday: :boolean,
                week: :boolean,
                has_paths: :boolean,
                path: :string,
                long: :boolean,
                duration: :string,
                quick: :boolean,
                fast: :boolean,
                instant: :boolean,
                slow: :boolean,
                background: :boolean,
                rare: :boolean,
                frequent: :boolean,
                unique: :boolean,
                shell: :string,
                tty: :string,
                with_args: :boolean,
                no_args: :boolean,
                arg_count: :integer,
                private: :boolean,
                no_private: :boolean,
                imported: :boolean,
                no_imported: :boolean,
                assisted: :boolean,
                no_assisted: :boolean,
                json: :boolean,
                yaml: :boolean,
                plain: :boolean,
                format: :string,
                limit: :integer,
                no_session: :boolean,
                no_start_time: :boolean,
                no_exit_code: :boolean,
                no_duration: :boolean,
                help: :boolean
              ]

  @aliases Options.common_aliases() ++ [c: :command, h: :help]

  def run(argv) do
    with {:ok, opts, args} <- Options.parse(argv, @switches, @aliases) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        run_query(opts, args)
      end
    end
  end

  defp run_query(opts, args) do
    with {:ok, opts} <- Options.normalize(opts),
         :ok <- reject_mutation(opts),
         :ok <- validate_format(output_format(opts)),
         :ok <- validate_regex(opts),
         :ok <- validate_duration(opts),
         {:ok, query_opts} <- query_options(opts),
         {:ok, rows} <- Query.executions(query_opts) do
      rows
      |> Filter.rows(args, opts)
      |> sort_rows(opts)
      |> unique_rows(opts)
      |> frequency_rows(opts)
      |> limit_rows(Keyword.get(opts, :limit))
      |> Render.write(output_format(opts))
    end
  end

  defp reject_mutation(opts) do
    if Keyword.get(opts, :delete, false) || Keyword.get(opts, :force_delete, false) do
      {:error, "query deletion is not supported by histlog v1 append-only storage"}
    else
      :ok
    end
  end

  defp query_options(opts) do
    {:ok, Keyword.take(opts, [:root, :date])}
  end

  defp sort_rows(rows, opts) do
    sorted = Enum.sort_by(rows, &(&1["timestamp"] || ""))

    if Keyword.get(opts, :desc, false), do: Enum.reverse(sorted), else: sorted
  end

  defp unique_rows(rows, opts) do
    if Keyword.get(opts, :unique, false), do: Enum.uniq_by(rows, & &1["command"]), else: rows
  end

  defp frequency_rows(rows, opts) do
    counts = Enum.frequencies_by(rows, & &1["command"])

    cond do
      Keyword.get(opts, :rare, false) ->
        Enum.filter(rows, &(Map.get(counts, &1["command"], 0) < 3))

      Keyword.get(opts, :frequent, false) ->
        Enum.filter(rows, &(Map.get(counts, &1["command"], 0) > 10))

      true ->
        rows
    end
  end

  defp limit_rows(rows, nil), do: rows
  defp limit_rows(rows, limit) when limit < 0, do: Enum.take(rows, abs(limit))
  defp limit_rows(rows, limit), do: Enum.take(rows, limit)

  defp output_format(opts) do
    cond do
      Keyword.get(opts, :json, false) -> "json"
      Keyword.get(opts, :yaml, false) -> "yaml"
      Keyword.get(opts, :plain, false) -> "plain"
      format = Keyword.get(opts, :format) -> format
      true -> "table"
    end
  end

  defp validate_format(format)
       when format in [
              "table",
              "json",
              "yaml",
              "plain",
              "bash",
              "zsh",
              "fish",
              "nu",
              "powershell"
            ],
       do: :ok

  defp validate_format(format), do: {:error, "unsupported query format #{inspect(format)}"}

  defp validate_regex(opts) do
    case Keyword.get(opts, :regex) do
      nil ->
        :ok

      pattern ->
        case Regex.compile(pattern) do
          {:ok, _regex} -> :ok
          {:error, {reason, position}} -> {:error, "invalid regex at #{position}: #{reason}"}
          {:error, reason} -> {:error, "invalid regex: #{inspect(reason)}"}
        end
    end
  end

  defp validate_duration(opts) do
    case Keyword.get(opts, :duration) do
      nil ->
        :ok

      value ->
        Duration.validate(value)
    end
  end

  defp help do
    """
    Usage: histlog query [search] [options]
            --regex PATTERN              Filter commands using regex
            --delete                     Unsupported in v1 append-only storage
            --force-delete               Unsupported in v1 append-only storage
            --asc                        Sort results ascending (oldest first) - DEFAULT
            --desc                       Sort results descending (newest first)
            --session ID                 Commands from a specific session ID
            --fuzzy                      Enable fuzzy matching for command text
            --command PATTERN            Filter by command text
            --dir PATH                   Commands executed in a specific directory
            --failed                     Only failed commands
            --success                    Only successful commands
            --exit CODE                  Commands with specific exit code
            --time TIME                  Filter by time range
            --since TIME                 Commands since specified time
            --before TIME                Commands before specified time
            --today                      Commands from today
            --yesterday                  Commands from yesterday
            --week                       Commands from this week
            --has-paths                  Commands that appear to reference filesystem paths
            --path PATH                  Commands or cwd containing a path
            --long                       Commands longer than 50 characters
            --duration DURATION          Duration filter, e.g. 2m, >10s, <0.5
            --quick                      Commands quicker than 1s
            --fast                       Commands quicker than 100ms
            --instant                    Commands quicker than 10ms
            --slow                       Commands slower than 10s
            --background                 Commands longer than 60s
            --rare                       Commands used fewer than 3 times
            --frequent                   Commands used more than 10 times
            --unique                     Remove duplicate commands
            --shell SHELL                Commands from a specific shell when captured
            --tty TTY                    Commands from a specific TTY when captured
            --with-args                  Commands that had arguments
            --no-args                    Commands without arguments
            --arg-count N                Commands with exactly N arguments
            --private                    Commands started with a space
            --no-private                 Exclude private commands
            --imported                   Show only imported commands
            --no-imported                Exclude imported commands
            --assisted                   Only show AI-assisted commands when captured
            --no-assisted                Exclude AI-assisted commands
            --json                       Output JSON with full metadata
            --yaml                       Output YAML with full metadata
            --plain                      Output only commands, one per line
            --format FORMAT              Output format: json, yaml, fish, zsh, nu, bash, powershell, plain
            --limit N                    Limit result count; negative N keeps the earliest N
            --no-session                 Only commands with no session_id
            --no-start-time              Only commands with no start time
            --no-exit-code               Only commands with no exit code
            --no-duration                Only commands with no duration
        -h, --help
    """
  end
end
