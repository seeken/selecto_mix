defmodule SelectoMix.MixProject do
  use Mix.Project

  def project do
    [
      app: :selecto_mix,
      version: "0.3.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:igniter, "~> 0.6"},
      {:ecto, "~> 3.10"},
      {:postgrex, ">= 0.0.0", optional: true},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Mix tasks and tooling for automatic Selecto configuration generation from Ecto schemas"
  end

  defp package do
    [
      maintainers: ["Selecto Team"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/selectodb/selecto_mix"}
    ]
  end
end
