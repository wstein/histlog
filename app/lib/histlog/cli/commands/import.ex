defmodule Histlog.CLI.Commands.Import do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Storage

  @switches Options.common_switches() ++
              [
                source: :string,
                session_id: :string,
                import_batch_id: :string
              ]

  @aliases Options.common_aliases()

  def run([file | argv]) do
    with {:ok, opts, []} <- Options.parse(argv, @switches, @aliases),
         {:ok, opts} <- Options.normalize(opts) do
      root = Storage.root(opts)
      date = Keyword.get(opts, :date, Date.utc_today())
      public_source = Keyword.get(opts, :source, source_name(file))
      source = internal_source(public_source)

      session_id =
        Keyword.get(opts, :session_id, "import-#{public_source}-#{Date.to_iso8601(date)}")

      import_batch_id =
        Keyword.get(opts, :import_batch_id, "#{public_source}-#{Date.to_iso8601(date)}")

      destination =
        Path.join(Storage.imports_dir(root), "#{Date.to_iso8601(date)}-#{public_source}.ndjson")

      with {:ok, content} <- File.read(file),
           {:ok, events} <-
             Histlog.Import.from_source(session_id, source, import_batch_id, content),
           output = Histlog.NDJSON.encode!(events),
           :ok <- Storage.atomic_write(destination, output) do
        IO.puts(destination)
        :ok
      else
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  def run([]), do: {:error, "missing import file"}

  defp internal_source("native"), do: "ndjson"
  defp internal_source(source), do: source

  defp source_name(file) do
    file
    |> Path.basename()
    |> String.replace(~r/[^A-Za-z0-9_.-]/, "_")
  end
end
