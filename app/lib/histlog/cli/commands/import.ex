defmodule Histlog.CLI.Commands.Import do
  @moduledoc false

  alias Histlog.CLI.Options
  alias Histlog.Storage

  @switches Options.common_switches() ++
              [
                source: :string,
                session_id: :string,
                import_batch_id: :string,
                help: :boolean
              ]

  @aliases Options.common_aliases() ++ [h: :help]

  def run(["--help"]), do: write_help()
  def run(["-h"]), do: write_help()
  def run([]), do: {:error, "missing import file"}

  def run([file | argv]) do
    with {:ok, opts, []} <- Options.parse(argv, @switches, @aliases),
         {:ok, opts} <- Options.normalize(opts) do
      if Keyword.get(opts, :help, false) do
        IO.write(help())
        :ok
      else
        run_import(file, opts)
      end
    end
  end

  defp run_import(file, opts) do
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

    report_path = destination <> ".report.json"

    with {:ok, content} <- File.read(file),
         {:ok, events, report} <-
           Histlog.Import.from_source_with_report(session_id, source, import_batch_id, content),
         output = Histlog.NDJSON.encode!(events),
         :ok <- Storage.atomic_write(destination, output),
         :ok <- Storage.atomic_write(report_path, JSON.encode!(report) <> "\n"),
         {:ok, _materialized} <- Histlog.Import.materialize(root, date, file, events, report) do
      IO.puts(destination)
      :ok
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp write_help do
    IO.write(help())
    :ok
  end

  defp internal_source("native"), do: "ndjson"
  defp internal_source(source), do: source

  defp source_name(file) do
    file
    |> Path.basename()
    |> String.replace(~r/[^A-Za-z0-9_.-]/, "_")
  end

  defp help do
    """
    Usage: histlog import FILE [options]

    Import existing shell history.

    Options:
      -h, --help                    Show this help
      -d, --date YYYY-MM-DD         Use a specific import date
      -r, --root PATH               Use a specific histlog data root
          --source SOURCE           zsh_history, bash_history, fish_history, or native
          --session-id ID           Override generated import session id
          --import-batch-id ID      Override generated import batch id
    """
  end
end
