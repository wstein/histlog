defmodule Histlog.MixProject do
  use Mix.Project

  def project do
    [
      app: :histlog,
      version: "0.1.0",
      elixir: "~> 1.17",
      escript: [main_module: Histlog.CLI],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Histlog.Application, []},
      extra_applications: [:crypto, :logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:exqlite, "~> 0.36"}
    ]
  end
end
