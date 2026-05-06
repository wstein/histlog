defmodule Histlog.CLI.Commands.Tail do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Storage

  @switches Options.common_switches() ++ [count: :integer]
  @aliases Options.common_aliases()

  def run(argv) do
    with {:ok, opts, []} <- Options.parse(argv, @switches, @aliases),
         {:ok, opts} <- Options.normalize(opts) do
      root = Storage.root(opts)
      date = Keyword.get(opts, :date, Date.utc_today())
      count = Keyword.get(opts, :count, 10)
      path = Storage.daily_events_path(root, date)

      if File.exists?(path) do
        path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.take(-count)
        |> Enum.each(&IO.puts/1)
      end

      :ok
    end
  end
end
