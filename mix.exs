defmodule Tringin.MixProject do
  use Mix.Project

  def project do
    [
      app: :tringin_ex,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :test
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Tringin.Application, []}
    ]
  end

  defp deps do
    [
      {:nimble_options, "~> 1.0"}
    ]
  end
end
