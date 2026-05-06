defmodule Histlog.CLI.Commands.Query do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Query

  @duration_shortcuts %{
    fast: {:lt, 100},
    instant: {:lt, 10},
    quick: {:lt, 1_000},
    slow: {:gt, 10_000},
    background: {:gt, 60_000}
  }

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
         {:ok, query_opts} <- query_options(opts),
         {:ok, rows} <- Query.executions(query_opts) do
      rows
      |> filter_rows(args, opts)
      |> sort_rows(opts)
      |> unique_rows(opts)
      |> frequency_rows(opts)
      |> limit_rows(Keyword.get(opts, :limit))
      |> write_rows(output_format(opts))
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

  defp filter_rows(rows, args, opts) do
    search = Enum.join(args, " ") |> blank_to_nil()
    command = Keyword.get(opts, :command) || search
    regex = compile_regex(Keyword.get(opts, :regex))
    duration = duration_filter(opts)
    time = time_filter(opts)

    rows
    |> Enum.filter(&match_command?(&1, command, Keyword.get(opts, :fuzzy, false)))
    |> Enum.filter(&match_regex?(&1, regex))
    |> Enum.filter(&match_dir?(&1, Keyword.get(opts, :dir)))
    |> Enum.filter(&match_status?(&1, opts))
    |> Enum.filter(&match_session?(&1, opts))
    |> Enum.filter(&match_shell?(&1, Keyword.get(opts, :shell)))
    |> Enum.filter(&match_tty?(&1, Keyword.get(opts, :tty)))
    |> Enum.filter(&match_time?(&1, time))
    |> Enum.filter(&match_duration?(&1, duration))
    |> Enum.filter(&match_length?(&1, opts))
    |> Enum.filter(&match_args?(&1, opts))
    |> Enum.filter(&match_private?(&1, opts))
    |> Enum.filter(&match_imported?(&1, opts))
    |> Enum.filter(&match_assisted?(&1, opts))
    |> Enum.filter(&match_missing?(&1, opts))
    |> Enum.filter(&match_paths?(&1, opts))
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

  defp write_rows(rows, "table") do
    rows
    |> table_lines()
    |> Enum.each(&IO.write(&1 <> "\n"))

    :ok
  end

  defp write_rows(rows, "json") do
    IO.puts(JSON.encode!(rows))
    :ok
  end

  defp write_rows(rows, "yaml") do
    IO.write(yaml_rows(rows))
    :ok
  end

  defp write_rows(rows, "plain") do
    Enum.each(rows, &IO.write(to_string(&1["command"]) <> "\n"))
    :ok
  end

  defp write_rows(rows, format) when format in ["bash", "zsh", "fish", "nu", "powershell"] do
    rows
    |> Enum.map(& &1["command"])
    |> Enum.each(&IO.write(shell_history_line(&1, format) <> "\n"))

    :ok
  end

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

  defp table_lines(rows) do
    labels = session_labels(rows)

    [
      "#{color("Sess", "38;5;141")} #{color("Timestamp", "38;5;14")}          #{color(" Duration", "33")} #{color("Exit", "38;5;84")} Command",
      "--------------------------------------------------"
      | Enum.map(rows, &table_row(&1, labels))
    ]
  end

  defp table_row(row, labels) do
    session = Map.get(labels, row["session_id"], "????") |> color("38;5;141")
    timestamp = row["timestamp"] |> format_timestamp() |> color("38;5;14")
    duration = row["duration_ms"] |> format_duration() |> color("33")
    exit = row["exit_status"] |> format_exit() |> color(exit_color(row["exit_status"]))
    command = row["command"] |> to_string() |> String.replace("\n", "\\n")

    "#{session} #{timestamp} #{duration} #{exit} #{command}"
  end

  defp session_labels(rows) do
    rows
    |> Enum.map(& &1["session_id"])
    |> Enum.uniq()
    |> Enum.with_index(1)
    |> Map.new(fn {session_id, index} ->
      {session_id, index |> Integer.to_string() |> String.pad_leading(4, "0")}
    end)
  end

  defp format_timestamp(nil), do: String.pad_trailing("?", 19)

  defp format_timestamp(timestamp) do
    timestamp
    |> local_timestamp()
    |> String.replace("T", " ")
    |> String.pad_trailing(19)
  end

  defp format_duration(nil), do: String.pad_leading("?", 9)

  defp format_duration(duration_ms) do
    seconds =
      duration_ms
      |> Kernel./(1000)
      |> :erlang.float_to_binary(decimals: 3)

    String.pad_leading("#{seconds}s", 9)
  end

  defp format_exit(nil), do: String.pad_trailing("?", 4)
  defp format_exit(0), do: String.pad_trailing("✓", 4)
  defp format_exit(status), do: "✗#{status}" |> String.slice(0, 4) |> String.pad_trailing(4)

  defp exit_color(nil), do: "38;5;8"
  defp exit_color(0), do: "38;5;84"
  defp exit_color(_status), do: "38;5;203"

  defp color(text, code), do: "\e[#{code}m#{text}\e[0m"

  defp match_command?(_row, nil, _fuzzy?), do: true
  defp match_command?(row, command, true), do: fuzzy_match?(row["command"] || "", command)
  defp match_command?(row, command, false), do: String.contains?(row["command"] || "", command)

  defp match_regex?(_row, nil), do: true
  defp match_regex?(row, {:ok, regex}), do: Regex.match?(regex, row["command"] || "")
  defp match_regex?(_row, {:error, _reason}), do: false

  defp match_dir?(_row, nil), do: true
  defp match_dir?(row, ""), do: row["cwd"] == File.cwd!()
  defp match_dir?(row, dir), do: Path.expand(row["cwd"] || "") == Path.expand(dir)

  defp match_status?(row, opts) do
    cond do
      Keyword.get(opts, :failed, false) -> row["exit_status"] not in [0, nil]
      Keyword.get(opts, :success, false) -> row["exit_status"] == 0
      exit = Keyword.get(opts, :exit) -> row["exit_status"] == exit
      exit = Keyword.get(opts, :exit_status) -> row["exit_status"] == exit
      true -> true
    end
  end

  defp match_session?(row, opts) do
    cond do
      Keyword.get(opts, :no_session, false) -> is_nil(row["session_id"])
      session = Keyword.get(opts, :session) -> row["session_id"] == session
      true -> true
    end
  end

  defp match_shell?(_row, nil), do: true
  defp match_shell?(row, shell), do: row["shell"] == shell

  defp match_tty?(_row, nil), do: true
  defp match_tty?(row, tty), do: row["tty"] == tty

  defp match_time?(_row, nil), do: true

  defp match_time?(row, {since, before}) do
    value = comparable_time(row["timestamp"])
    after_since? = is_nil(since) || (!is_nil(value) && value >= since)
    before_before? = is_nil(before) || (!is_nil(value) && value <= before)
    after_since? && before_before?
  end

  defp match_duration?(_row, nil), do: true
  defp match_duration?(%{"duration_ms" => nil}, _duration), do: false
  defp match_duration?(row, {:lt, ms}), do: row["duration_ms"] < ms
  defp match_duration?(row, {:gt, ms}), do: row["duration_ms"] > ms
  defp match_duration?(row, {:eq, ms}), do: row["duration_ms"] == ms

  defp match_length?(row, opts) do
    !Keyword.get(opts, :long, false) || String.length(row["command"] || "") > 50
  end

  defp match_args?(row, opts) do
    count = arg_count(row["command"] || "")

    cond do
      Keyword.get(opts, :with_args, false) -> count > 0
      Keyword.get(opts, :no_args, false) -> count == 0
      expected = Keyword.get(opts, :arg_count) -> count == expected
      true -> true
    end
  end

  defp match_private?(row, opts) do
    private? = String.starts_with?(row["command"] || "", " ")

    cond do
      Keyword.get(opts, :private, false) -> private?
      Keyword.get(opts, :no_private, false) -> !private?
      true -> true
    end
  end

  defp match_imported?(row, opts) do
    imported? = row["source"] == "imported" || is_nil(row["session_id"])

    cond do
      Keyword.get(opts, :imported, false) -> imported?
      Keyword.get(opts, :no_imported, false) -> !imported?
      true -> true
    end
  end

  defp match_assisted?(row, opts) do
    assisted? = row["assisted"] == true

    cond do
      Keyword.get(opts, :assisted, false) -> assisted?
      Keyword.get(opts, :no_assisted, false) -> !assisted?
      true -> true
    end
  end

  defp match_missing?(row, opts) do
    (!Keyword.get(opts, :no_start_time, false) || is_nil(row["timestamp"])) &&
      (!Keyword.get(opts, :no_exit_code, false) || is_nil(row["exit_status"])) &&
      (!Keyword.get(opts, :no_duration, false) || is_nil(row["duration_ms"]))
  end

  defp match_paths?(row, opts) do
    command = row["command"] || ""
    has_path? = Regex.match?(~r/(^|\s)(\.{1,2}(\/|\s|$)|\/|~)/, command)

    cond do
      path = Keyword.get(opts, :path) ->
        String.contains?(command, path) || String.contains?(row["cwd"] || "", path)

      Keyword.get(opts, :has_paths, false) ->
        has_path?

      true ->
        true
    end
  end

  defp fuzzy_match?(text, pattern) do
    text = String.downcase(text)

    pattern
    |> String.downcase()
    |> String.graphemes()
    |> Enum.reduce_while(text, fn char, rest ->
      case String.split(rest, char, parts: 2) do
        [_before, after_match] -> {:cont, after_match}
        _ -> {:halt, false}
      end
    end)
    |> is_binary()
  end

  defp arg_count(command) do
    case String.split(String.trim(command), ~r/\s+/, trim: true) do
      [] -> 0
      [_command | args] -> length(args)
    end
  end

  defp compile_regex(nil), do: nil

  defp compile_regex(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> {:ok, regex}
      {:error, reason} -> {:error, reason}
    end
  end

  defp duration_filter(opts) do
    shortcut =
      Enum.find_value(@duration_shortcuts, fn {flag, filter} ->
        if Keyword.get(opts, flag, false), do: filter
      end)

    shortcut || parse_duration_filter(Keyword.get(opts, :duration))
  end

  defp parse_duration_filter(nil), do: nil

  defp parse_duration_filter(value) do
    {operator, value} =
      case value do
        ">" <> rest -> {:gt, rest}
        "<" <> rest -> {:lt, rest}
        other -> {:eq, other}
      end

    {operator, duration_ms(value)}
  end

  defp duration_ms(value) do
    case Regex.run(~r/^([0-9]+(?:\.[0-9]+)?)(ms|s|m|h|d|w)?$/, String.trim(value)) do
      [_, number, unit] ->
        multiplier = %{
          "ms" => 1,
          "s" => 1_000,
          "" => 1_000,
          "m" => 60_000,
          "h" => 3_600_000,
          "d" => 86_400_000,
          "w" => 604_800_000
        }

        {parsed, ""} = Float.parse(number)
        round(parsed * Map.fetch!(multiplier, unit || ""))

      _ ->
        -1
    end
  end

  defp time_filter(opts) do
    cond do
      Keyword.get(opts, :week, false) ->
        today = local_today()
        {Date.add(today, -Date.day_of_week(today) + 1) |> Date.to_iso8601(), nil}

      Keyword.get(opts, :today, false) ->
        today = local_today() |> Date.to_iso8601()
        {today, today <> "T23:59:59"}

      Keyword.get(opts, :yesterday, false) ->
        yesterday = local_today() |> Date.add(-1) |> Date.to_iso8601()
        {yesterday, yesterday <> "T23:59:59"}

      time = Keyword.get(opts, :time) ->
        parse_time_range(time)

      since = Keyword.get(opts, :since) ->
        {normalize_time(since), normalize_time(Keyword.get(opts, :before))}

      before = Keyword.get(opts, :before) ->
        {nil, normalize_time(before)}

      true ->
        nil
    end
  end

  defp parse_time_range(value) do
    cond do
      Regex.match?(~r/^\d+w$/, value) ->
        weeks = value |> String.trim_trailing("w") |> String.to_integer()
        {Date.add(Date.utc_today(), -7 * weeks) |> Date.to_iso8601(), nil}

      String.contains?(value, "..") ->
        [since, before] = String.split(value, "..", parts: 2)

        {blank_to_nil(since) && normalize_time(since),
         blank_to_nil(before) && normalize_time(before)}

      true ->
        {normalize_time(value), nil}
    end
  end

  defp normalize_time(nil), do: nil

  defp normalize_time(value) do
    value = String.trim(value)

    cond do
      Regex.match?(~r/^\d{2}:\d{2}/, value) -> Date.to_iso8601(local_today()) <> "T#{value}"
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, value) -> value
      true -> String.replace(value, " ", "T")
    end
  end

  defp comparable_time(nil), do: nil
  defp comparable_time(value), do: local_timestamp(value)

  defp local_today do
    {{year, month, day}, _time} = :calendar.local_time()
    Date.new!(year, month, day)
  end

  defp local_timestamp(timestamp) do
    with {:ok, datetime, _offset} <- DateTime.from_iso8601(to_string(timestamp)) do
      datetime
      |> DateTime.to_unix(:second)
      |> :calendar.system_time_to_local_time(:second)
      |> format_local_time()
    else
      _error ->
        timestamp
        |> to_string()
        |> String.replace(" ", "T")
        |> String.replace_suffix("Z", "")
        |> String.slice(0, 19)
    end
  end

  defp format_local_time({{year, month, day}, {hour, minute, second}}) do
    [
      pad(year, 4),
      "-",
      pad(month, 2),
      "-",
      pad(day, 2),
      "T",
      pad(hour, 2),
      ":",
      pad(minute, 2),
      ":",
      pad(second, 2)
    ]
    |> IO.iodata_to_binary()
  end

  defp pad(value, count), do: value |> Integer.to_string() |> String.pad_leading(count, "0")

  defp shell_history_line(command, format) when format in ["bash", "zsh", "fish"],
    do: command || ""

  defp shell_history_line(command, "nu"), do: command || ""
  defp shell_history_line(command, "powershell"), do: command || ""

  defp yaml_rows(rows) do
    Enum.map_join(rows, "", fn row ->
      "- command: #{yaml_scalar(row["command"])}\n" <>
        "  timestamp: #{yaml_scalar(row["timestamp"])}\n" <>
        "  cwd: #{yaml_scalar(row["cwd"])}\n" <>
        "  exit_status: #{yaml_scalar(row["exit_status"])}\n" <>
        "  duration_ms: #{yaml_scalar(row["duration_ms"])}\n" <>
        "  session_id: #{yaml_scalar(row["session_id"])}\n"
    end)
  end

  defp yaml_scalar(nil), do: "null"
  defp yaml_scalar(value) when is_integer(value), do: Integer.to_string(value)
  defp yaml_scalar(value), do: inspect(to_string(value))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

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
