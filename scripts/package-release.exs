#!/usr/bin/env elixir

defmodule Histlog.PackageRelease do
  @moduledoc false

  def main(argv \\ System.argv()) do
    version =
      argv
      |> List.first()
      |> normalize_version!()

    platform = platform!()
    dist = Path.expand("dist")
    package_name = "histlog-#{platform}-v#{version}"
    package_root = Path.join(dist, package_name)
    tarball = Path.join(dist, package_name <> ".tar.gz")
    checksum_path = tarball <> ".sha256"

    File.rm_rf!(package_root)
    File.mkdir_p!(package_root)

    copy_required!("app/histlog", Path.join(package_root, "histlog"))
    copy_required!("app/histlog.escript", Path.join(package_root, "histlog.escript"))
    copy_required!("app/_build/dev/lib", Path.join(package_root, "lib"))

    File.rm(tarball)

    tar!("dist", package_name, tarball)

    checksum = sha256!(tarball)
    File.write!(checksum_path, checksum <> "  " <> Path.basename(tarball) <> "\n")

    IO.puts(tarball)
    IO.puts(checksum_path)
  rescue
    exception ->
      IO.puts(:stderr, Exception.message(exception))
      System.halt(1)
  end

  defp normalize_version!(nil), do: raise("VERSION is required")

  defp normalize_version!(version) do
    version = version |> String.trim() |> String.replace(~r/^v/i, "")

    if Regex.match?(~r/^\d+\.\d+\.\d+(?:[-+].+)?$/, version) do
      version
    else
      raise "invalid version: #{inspect(version)}"
    end
  end

  defp platform! do
    case {:os.type(), :erlang.system_info(:system_architecture) |> List.to_string()} do
      {{:unix, :darwin}, arch} ->
        cond do
          String.contains?(arch, "aarch64") or String.contains?(arch, "arm64") ->
            "darwin-arm64"

          String.contains?(arch, "x86_64") ->
            "darwin-x86_64"

          true ->
            "darwin-#{sanitize_arch(arch)}"
        end

      {{:unix, :linux}, arch} ->
        if String.contains?(arch, "x86_64") do
          "linux-x86_64"
        else
          "linux-#{sanitize_arch(arch)}"
        end

      {os, arch} ->
        raise "unsupported release platform: #{inspect(os)} #{arch}"
    end
  end

  defp sanitize_arch(arch), do: String.replace(arch, ~r/[^A-Za-z0-9_.-]/, "-")

  defp copy_required!(source, destination) do
    unless File.exists?(source) do
      raise "missing required release input: #{source}"
    end

    if File.dir?(source) do
      File.cp_r!(source, destination)
    else
      File.cp!(source, destination)
      File.chmod!(destination, 0o755)
    end
  end

  defp tar!(cwd, package_name, tarball) do
    {output, status} =
      System.cmd("tar", ["-czf", Path.expand(tarball), "-C", package_name, "."],
        cd: cwd,
        stderr_to_stdout: true
      )

    if status != 0 do
      raise output
    end
  end

  defp sha256!(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end

Histlog.PackageRelease.main()
