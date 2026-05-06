defmodule Histlog.Query do
  @moduledoc """
  Streaming file-based query helpers for derived execution rows.
  """

  alias Histlog.Storage

  @doc """
  Returns derived execution rows for a date matching simple filters.
  """
  def executions(opts \\ []) do
    root = Storage.root(opts)
    date = Keyword.get(opts, :date, Date.utc_today())
    filters = Keyword.get(opts, :filters, %{})
    path = Storage.daily_exec_path(root, date)

    if File.exists?(path) do
      rows =
        path
        |> File.stream!(:line, [])
        |> Stream.map(&JSON.decode!/1)
        |> Stream.filter(&matches?(&1, filters))
        |> Enum.to_list()

      {:ok, rows}
    else
      {:ok, []}
    end
  end

  defp matches?(row, filters) do
    Enum.all?(filters, fn
      {:command, command} -> String.contains?(row["command"] || "", command)
      {:cwd, cwd} -> row["cwd"] == cwd
      {:exit_status, status} -> row["exit_status"] == status
      {field, value} -> row[to_string(field)] == value
    end)
  end
end
