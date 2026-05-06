defmodule Histlog.Verifier do
  @moduledoc """
  Verification for daily materialization files and manifests.
  """

  alias Histlog.Manifest
  alias Histlog.Storage

  @doc """
  Recomputes daily materialization counts and checksums for a date.
  """
  def verify(opts \\ []) do
    root = Storage.root(opts)
    date = Keyword.get(opts, :date, Date.utc_today())
    manifest_path = Storage.manifest_path(root, date)

    with {:ok, manifest} <- read_manifest(manifest_path) do
      report = build_report(root, date, manifest)

      if report["ok"] do
        {:ok, report}
      else
        {:error, report}
      end
    end
  end

  defp read_manifest(path) do
    case File.read(path) do
      {:ok, content} ->
        JSON.decode(content)

      {:error, :enoent} ->
        {:error, manifest_missing_report(path)}

      {:error, reason} ->
        {:error, %{"ok" => false, "errors" => [inspect(reason)], "manifest_path" => path}}
    end
  end

  defp build_report(root, date, manifest) do
    daily =
      verify_file(
        Storage.daily_events_path(root, date),
        manifest["records_written"],
        manifest["checksum"]
      )

    exec =
      verify_file(
        Storage.daily_exec_path(root, date),
        manifest["exec_records_written"],
        manifest["exec_checksum"]
      )

    errors =
      []
      |> add_errors("daily", daily)
      |> add_errors("exec", exec)

    %{
      "ok" => errors == [],
      "date" => Date.to_iso8601(date),
      "manifest_path" => Storage.manifest_path(root, date),
      "errors" => errors,
      "checks" => %{
        "daily" => daily,
        "exec" => exec
      }
    }
  end

  defp verify_file(path, expected_records, expected_checksum) do
    case File.read(path) do
      {:ok, content} ->
        actual_records = count_ndjson_records(content)
        actual_checksum = Manifest.checksum(content)

        %{
          "ok" => actual_records == expected_records and actual_checksum == expected_checksum,
          "path" => path,
          "records_expected" => expected_records,
          "records_actual" => actual_records,
          "checksum_expected" => expected_checksum,
          "checksum_actual" => actual_checksum
        }

      {:error, reason} ->
        %{
          "ok" => false,
          "path" => path,
          "records_expected" => expected_records,
          "records_actual" => nil,
          "checksum_expected" => expected_checksum,
          "checksum_actual" => nil,
          "error" => inspect(reason)
        }
    end
  end

  defp add_errors(errors, _name, %{"ok" => true}), do: errors

  defp add_errors(errors, name, %{"error" => reason}) do
    errors ++ ["#{name}: #{reason}"]
  end

  defp add_errors(errors, name, check) do
    count_error =
      if check["records_expected"] == check["records_actual"] do
        []
      else
        [
          "#{name}: records expected #{inspect(check["records_expected"])} got #{inspect(check["records_actual"])}"
        ]
      end

    checksum_error =
      if check["checksum_expected"] == check["checksum_actual"] do
        []
      else
        ["#{name}: checksum mismatch"]
      end

    errors ++ count_error ++ checksum_error
  end

  defp manifest_missing_report(path) do
    %{
      "ok" => false,
      "manifest_path" => path,
      "errors" => ["manifest_missing"]
    }
  end

  defp count_ndjson_records(""), do: 0

  defp count_ndjson_records(content) do
    content
    |> String.split("\n", trim: true)
    |> length()
  end
end
