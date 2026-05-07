defmodule Histlog.CLI.Commands.Paths do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Query
  alias Histlog.Query.Paths

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
      |> Paths.rows()
      |> filter_rows(search)
      |> Enum.sort_by(fn row -> row.path end)
      |> limit_rows(Keyword.get(opts, :limit))
      |> write_rows(output_format(opts))
    end
  end

  defp filter_rows(rows, ""), do: rows
  defp filter_rows(rows, search), do: Enum.filter(rows, &String.contains?(&1.path, search))

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
