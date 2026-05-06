defmodule Histlog.Import do
  @moduledoc """
  Import helpers that model external history as synthetic histlog events.
  """

  alias Histlog.Event

  @doc """
  Builds an import batch event stream from simple execution maps.
  """
  def batch(session_id, source, import_batch_id, executions) when is_list(executions) do
    started =
      Event.new!("import_batch_started", session_id, 1, %{
        "source" => source,
        "import_batch_id" => import_batch_id
      })

    imported =
      executions
      |> Enum.with_index(2)
      |> Enum.map(fn {execution, seq} ->
        Event.new!(
          "imported_execution",
          session_id,
          seq,
          Map.take(execution, ["command", "cwd", "timestamp", "exit_status"])
        )
      end)

    finished =
      Event.new!("import_batch_finished", session_id, length(executions) + 2, %{
        "import_batch_id" => import_batch_id,
        "records" => length(executions)
      })

    [started | imported] ++ [finished]
  end
end
