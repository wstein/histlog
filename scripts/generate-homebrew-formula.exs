#!/usr/bin/env elixir

defmodule Histlog.GenerateHomebrewFormula do
  @moduledoc false

  def main(argv \\ System.argv()) do
    {opts, args, invalid} =
      OptionParser.parse(argv,
        strict: [tarball: :string, output: :string],
        aliases: [t: :tarball, o: :output]
      )

    if invalid != [] do
      raise "invalid options: #{inspect(invalid)}"
    end

    version =
      args
      |> List.first()
      |> normalize_version!()

    tarball = Keyword.get(opts, :tarball) || raise "--tarball is required"
    output = Keyword.get(opts, :output, "dist/histlog.rb")

    unless File.exists?(tarball) do
      raise "tarball does not exist: #{tarball}"
    end

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, formula(version, tarball))
    IO.puts(output)
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

  defp formula(version, tarball) do
    basename = Path.basename(tarball)
    sha = sha256!(tarball)

    """
    class Histlog < Formula
      desc "Log-structured shell history with NDJSON capture and SQLite query projection"
      homepage "https://github.com/wstein/histlog"
      url "https://github.com/wstein/histlog/releases/download/v#{version}/#{basename}"
      sha256 "#{sha}"
      license "MIT"

      depends_on "elixir"

      def install
        libexec.install Dir["*"]
        bin.install_symlink libexec/"histlog" => "histlog"
      end

      test do
        assert_match "histlog", shell_output("\#{bin}/histlog --help")
        system "\#{bin}/histlog", "consolidate", "--root", testpath/"histlog-root", "--date", "2026-05-07"
        system "\#{bin}/histlog", "doctor", "zsh", "--root", testpath/"histlog-root", "--date", "2026-05-07"
      end
    end
    """
  end

  defp sha256!(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end

Histlog.GenerateHomebrewFormula.main()
