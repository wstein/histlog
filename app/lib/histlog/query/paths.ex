defmodule Histlog.Query.Paths do
  @moduledoc """
  Semantic path summaries derived from query execution rows.
  """

  def rows(execution_rows) do
    exec_counts = Enum.frequencies(Enum.flat_map(execution_rows, &cwd_path/1))
    arg_counts = Enum.frequencies(Enum.flat_map(execution_rows, &materialized_argument_paths/1))

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

  defp materialized_argument_paths(%{"paths" => paths}) when is_list(paths) and paths != [] do
    Enum.flat_map(paths, fn path ->
      case path["path"] || path["resolved_path"] do
        value when is_binary(value) and value != "" -> [value]
        _other -> []
      end
    end)
  end

  defp materialized_argument_paths(row), do: argument_paths(row)

  defp argument_paths(%{"command" => command, "cwd" => cwd}) when is_binary(command) do
    command
    |> command_tokens()
    |> Enum.drop(1)
    |> Enum.flat_map(&existing_path(&1, cwd))
  end

  defp argument_paths(_row), do: []

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
end
