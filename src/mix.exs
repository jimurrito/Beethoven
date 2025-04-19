defmodule Beethoven.MixProject do
  use Mix.Project

  def project do
    [
      name: "Beethoven",
      app: :beethoven,
      version: "0.2.5",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  defp description() do
    "A Decentralized failover and peer-to-peer node finder for Elixir. Allows Elixir nodes to find each other automatically. Once connected, they can coordinate to delegate roles and tasks between the nodes in the cluster. Written using only the Elixir and Erlang standard library."
  end

  defp package() do
    [
      # This option is only needed when you don't want to use the OTP application name
      name: "beethoven",
      # These are the default files included in the package
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["GPL-3.0-or-later"],
      links: %{"GitHub" => "https://github.com/jimurrito/beethoven"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    if Mix.env() == :prod do
      [
        mod: {Beethoven.Application, []},
        extra_applications: [:logger, :runtime_tools, :mnesia]
      ]
    else
      [
        mod: {Beethoven.Application, []},
        extra_applications: [:logger, :runtime_tools, :mnesia, :wx, :observer]
      ]
    end
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
