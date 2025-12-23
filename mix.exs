defmodule Madness.MixProject do
  use Mix.Project

  def project do
    [
      app: :madness,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Madness.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:typedstruct, "~> 0.5", runtime: false},
      {:inertial, "~> 2.0.0"}
    ]
  end
end
