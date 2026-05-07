defmodule Histlog.Query.Statistics do
  @moduledoc """
  High-level statistics derived from query execution rows.
  """

  alias Histlog.Query.Commands
  alias Histlog.Query.Paths

  def summary(rows, opts \\ []) do
    top_limit = Keyword.get(opts, :top_limit, 10)
    timestamps = rows |> Enum.map(& &1["timestamp"]) |> Enum.reject(&is_nil/1) |> Enum.sort()

    {:ok, top_commands} =
      Commands.rows(rows, sort_by: "count", limit: top_limit)

    top_paths =
      rows
      |> Paths.rows()
      |> Enum.sort_by(&{&1.exec + &1.args, &1.path})
      |> Enum.reverse()
      |> Enum.take(top_limit)

    %{
      total_commands: length(rows),
      unique_commands:
        rows |> Enum.map(& &1["command"]) |> Enum.reject(&blank?/1) |> Enum.uniq() |> length(),
      sessions:
        rows |> Enum.map(& &1["session_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length(),
      imported_commands: Enum.count(rows, &(&1["source"] == "import")),
      live_commands: Enum.count(rows, &(&1["source"] == "live")),
      successful_commands: Enum.count(rows, &(&1["exit_status"] == 0)),
      failed_commands:
        Enum.count(rows, &(is_integer(&1["exit_status"]) && &1["exit_status"] != 0)),
      first_seen: List.first(timestamps),
      last_seen: List.last(timestamps),
      top_commands: top_commands,
      top_paths: top_paths
    }
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
