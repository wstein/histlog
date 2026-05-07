defmodule Histlog.PathAnalyzer do
  @moduledoc """
  Derives filesystem path references from command text.

  This runs during materialization, not shell capture. The analyzer is deliberately
  conservative: it records path-shaped arguments and existing relative arguments,
  but never executes shell code.
  """

  @token_pattern ~r/(?:'[^']*'|"[^"]*"|\S+)/

  def command_paths(command, cwd) when is_binary(command) do
    command
    |> tokens()
    |> Enum.drop(1)
    |> Enum.with_index()
    |> Enum.flat_map(fn {token, index} ->
      case analyze_token(token, cwd, index) do
        nil -> []
        path -> [path]
      end
    end)
  end

  def command_paths(_command, _cwd), do: []

  defp tokens(command) do
    @token_pattern
    |> Regex.scan(command)
    |> Enum.map(fn [token] -> strip_quotes(token) end)
    |> Enum.reject(&(&1 == ""))
  end

  defp strip_quotes(token) do
    token
    |> String.trim()
    |> String.trim_leading("'")
    |> String.trim_trailing("'")
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end

  defp analyze_token(token, cwd, index) do
    cond do
      skip_token?(token) ->
        nil

      path_like?(token) ->
        build_path(token, cwd, index)

      true ->
        resolved = resolve(token, cwd)
        if File.exists?(resolved), do: build_path(token, cwd, index), else: nil
    end
  end

  defp skip_token?(token) do
    String.starts_with?(token, "-") ||
      String.contains?(token, "://") ||
      String.match?(token, ~r/^\d+$/) ||
      String.match?(token, ~r/^[A-Za-z_][A-Za-z0-9_]*=/) ||
      token in ["|", ">", ">>", "<", "2>", "2>>", "&>", "&&", "||", ";"]
  end

  defp path_like?(token) do
    String.starts_with?(token, ["/", "~", "./", "../"]) ||
      token in [".", ".."] ||
      String.contains?(token, "/")
  end

  defp build_path(token, cwd, index) do
    resolved = resolve(token, cwd)

    %{
      "arg_position" => index,
      "original_arg" => token,
      "resolved_path" => resolved,
      "exists" => File.exists?(resolved),
      "type" => path_type(resolved)
    }
  end

  defp resolve("~" <> _rest = path, _cwd), do: Path.expand(path)
  defp resolve(path, cwd) when is_binary(cwd) and cwd != "", do: Path.expand(path, cwd)
  defp resolve(path, _cwd), do: Path.expand(path)

  defp path_type(path) do
    cond do
      File.dir?(path) -> "d"
      File.regular?(path) -> "f"
      true -> "u"
    end
  end
end
