defmodule Histlog.CLI.Commands.Paths do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Query

  @switches Options.common_switches() ++
              [
                limit: :integer,
                json: :boolean,
                plain: :boolean,
                help: :boolean
              ]

  @aliases Options.common_aliases() ++ [h: :help]

  def run(argv) do
    with {:ok, opts, args} <- Options.parse(argv, @switches, @aliases) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        run_paths(opts, Enum.join(args, " "))
      end
    end
  end

  defp run_paths(opts, search) do
    with {:ok, opts} <- Options.normalize(opts),
         {:ok, rows} <- Query.executions(Keyword.take(opts, [:root, :date])) do
      rows
      |> path_rows()
      |> filter_rows(search)
      |> Enum.sort_by(fn row -> row.path end)
      |> limit_rows(Keyword.get(opts, :limit))
      |> write_rows(output_format(opts))
    end
  end

  defp filter_rows(rows, ""), do: rows
  defp filter_rows(rows, search), do: Enum.filter(rows, &String.contains?(&1.path, search))

  defp path_rows(rows) do
    exec_counts = Enum.frequencies(Enum.flat_map(rows, &cwd_path/1))
    arg_counts = Enum.frequencies(Enum.flat_map(rows, &materialized_argument_paths/1))

    [Map.keys(exec_counts), Map.keys(arg_counts)]
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.map(fn path ->
      %{
        exec: Map.get(exec_counts, path, 0),
        args: Map.get(arg_counts, path, 0),
        path: path
      }
    end)
  end

  defp cwd_path(%{"cwd" => cwd}) when is_binary(cwd) and cwd != "", do: [normalize_path(cwd, cwd)]
  defp cwd_path(_row), do: []

  defp argument_paths(%{"command" => command, "cwd" => cwd}) when is_binary(command) do
    command
    |> command_tokens()
    |> Enum.drop(1)
    |> Enum.flat_map(&existing_path(&1, cwd))
  end

  defp argument_paths(_row), do: []

  defp materialized_argument_paths(%{"paths" => paths}) when is_list(paths) and paths != [] do
    Enum.flat_map(paths, fn path ->
      case path["path"] || path["resolved_path"] do
        value when is_binary(value) and value != "" -> [value]
        _other -> []
      end
    end)
  end

  defp materialized_argument_paths(row), do: argument_paths(row)

  defp command_tokens(command) do
    ~r/(?:'[^']*'|"[^"]*"|\S+)/
    |> Regex.scan(command)
    |> Enum.map(fn [token] -> token |> String.trim("'\"") |> String.trim() end)
    |> Enum.reject(&(&1 == ""))
  end

  defp existing_path(token, cwd) do
    path = normalize_path(token, cwd)

    if path_argument?(token) && File.exists?(path), do: [path], else: []
  end

  defp path_argument?(token),
    do: !String.starts_with?(token, "-") && !String.contains?(token, "://")

  defp normalize_path("~" <> rest, _cwd), do: Path.expand("~" <> rest)
  defp normalize_path(path, cwd) when is_binary(cwd) and cwd != "", do: Path.expand(path, cwd)
  defp normalize_path(path, _cwd), do: Path.expand(path)

  defp limit_rows(rows, nil), do: rows
  defp limit_rows(rows, limit), do: Enum.take(rows, limit)

  defp write_rows(rows, "table") do
    IO.write(color("  Exec", "38;5;207") <> " " <> color("  Args", "38;5;80") <> " Path\n")
    IO.write("-------------------------\n")

    Enum.each(rows, fn row ->
      IO.write(
        color(row.exec |> Integer.to_string() |> String.pad_leading(6), "38;5;207") <>
          " " <>
          color(row.args |> Integer.to_string() |> String.pad_leading(6), "38;5;80") <>
          " " <>
          color_path(row.path) <>
          "\n"
      )
    end)

    :ok
  end

  defp write_rows(rows, "json") do
    rows
    |> JSON.encode!()
    |> IO.puts()

    :ok
  end

  defp write_rows(rows, "plain") do
    Enum.each(rows, &IO.write(&1.path <> "\n"))
    :ok
  end

  defp output_format(opts) do
    cond do
      Keyword.get(opts, :json, false) -> "json"
      Keyword.get(opts, :plain, false) -> "plain"
      true -> "table"
    end
  end

  defp color_path(path) do
    if String.ends_with?(path, "/") || File.dir?(path) do
      color(String.trim_trailing(path, "/") <> "/", "38;5;12")
    else
      path
    end
  end

  defp color(text, code), do: "\e[#{code}m#{text}\e[0m"

  defp help do
    """
    Usage: histlog paths [options]
            --date YYYY-MM-DD           Summarize paths for one date
            --root PATH                 Use a specific histlog data root
            --limit N                   Limit number of paths
            --json                      Output JSON with exec/args/path fields
            --plain                     Output only paths, one per line
        -h, --help
    """
  end
end
