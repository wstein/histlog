defmodule Histlog.Query.Filter do
  @moduledoc false

  alias Histlog.Query.Duration
  alias Histlog.Query.Time

  def rows(rows, args, opts) do
    search = Enum.join(args, " ") |> blank_to_nil()
    command = Keyword.get(opts, :command) || search
    regex = compile_regex(Keyword.get(opts, :regex))
    duration = Duration.filter(opts)
    time = Time.filter(opts)

    rows
    |> Enum.filter(&match_command?(&1, command, Keyword.get(opts, :fuzzy, false)))
    |> Enum.filter(&match_regex?(&1, regex))
    |> Enum.filter(&match_dir?(&1, Keyword.get(opts, :dir)))
    |> Enum.filter(&match_status?(&1, opts))
    |> Enum.filter(&match_session?(&1, opts))
    |> Enum.filter(&match_shell?(&1, Keyword.get(opts, :shell)))
    |> Enum.filter(&match_tty?(&1, Keyword.get(opts, :tty)))
    |> Enum.filter(&Time.match?(&1, time))
    |> Enum.filter(&Duration.match?(&1, duration))
    |> Enum.filter(&match_length?(&1, opts))
    |> Enum.filter(&match_args?(&1, opts))
    |> Enum.filter(&match_private?(&1, opts))
    |> Enum.filter(&match_imported?(&1, opts))
    |> Enum.filter(&match_assisted?(&1, opts))
    |> Enum.filter(&match_missing?(&1, opts))
    |> Enum.filter(&match_paths?(&1, opts))
  end

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
    private? = row["is_private"] in [1, true]

    cond do
      Keyword.get(opts, :private, false) -> private?
      Keyword.get(opts, :no_private, false) || disabled_boolean?(opts, :private) -> !private?
      true -> true
    end
  end

  defp match_imported?(row, opts) do
    imported? = row["source"] in ["import", "imported"] || is_nil(row["session_id"])

    cond do
      Keyword.get(opts, :imported, false) -> imported?
      Keyword.get(opts, :no_imported, false) || disabled_boolean?(opts, :imported) -> !imported?
      true -> true
    end
  end

  defp match_assisted?(row, opts) do
    assisted? = row["is_assisted"] in [1, true] || row["assisted"] == true

    cond do
      Keyword.get(opts, :assisted, false) -> assisted?
      Keyword.get(opts, :no_assisted, false) || disabled_boolean?(opts, :assisted) -> !assisted?
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
    paths = row["paths"] || []
    has_path? = paths != [] || Regex.match?(~r/(^|\s)(\.{1,2}(\/|\s|$)|\/|~)/, command)

    cond do
      path = Keyword.get(opts, :path) ->
        path_matches?(paths, path) ||
          String.contains?(command, path) || String.contains?(row["cwd"] || "", path)

      Keyword.get(opts, :has_paths, false) ->
        has_path?

      true ->
        true
    end
  end

  defp path_matches?(paths, path) do
    Enum.any?(paths, fn path_row ->
      Enum.any?(["path", "resolved_path", "original_arg"], fn key ->
        path_row
        |> Map.get(key)
        |> to_string()
        |> String.contains?(path)
      end)
    end)
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

  defp disabled_boolean?(opts, key), do: Keyword.fetch(opts, key) == {:ok, false}

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
