defmodule Packmatic.MixProject do
  use Mix.Project

  def project do
    [
      app: :packmatic,
      version: "2.0.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(:dev) ++ deps(:test) ++ deps(:prod),
      dialyzer: dialyzer(),
      name: "Packmatic",
      description: "Streaming Zip64 archive generation",
      source_url: "https://github.com/evadne/packmatic",
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp dialyzer do
    [
      plt_add_apps: [:mix, :iex, :ex_unit],
      flags: ~w(error_handling extra_return missing_return unmatched_returns underspecs)a,
      list_unused_filters: true
    ]
  end

  defp deps(:dev) do
    [
      {:dialyxir, "~> 1.4.7", only: :dev, runtime: false},
      {:ex_doc, "~> 0.39.1", only: :dev, runtime: false}
    ]
  end

  defp deps(:test) do
    [
      {:briefly, "~> 0.5.1", only: [:test, :dev]},
      {:bypass, "~> 2.1.0", only: [:test, :dev]},
      {:cowboy, "~> 2.14.2", only: [:test, :dev]},
      {:incendium, "~> 0.5.0", only: [:test, :dev]},
      {:mox, "~> 1.2.0", only: [:test, :dev]},
      {:plug_cowboy, "~> 2.7.5", only: [:test, :dev]},
      {:plug, "~> 1.18.1", only: [:test, :dev]},
      {:stream_data, "~> 1.2.0", only: [:test, :dev]},
      {:teamcity_formatter, github: "prook/teamcity_formatter", only: [:test, :dev], runtime: false},
      {:timex, "~> 3.7.13", only: [:test, :dev]}
    ]
  end

  defp deps(:prod) do
    [
      {:req, "~> 0.5.16"}
    ]
  end

  defp package do
    [
      maintainers: ["Evadne Wu"],
      files: package_files(),
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/evadne/packmatic"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      nest_modules_by_prefix: [
        Packmatic.Manifest,
        Packmatic.Source,
        Packmatic.Compressor,
        Packmatic.Field,
        Packmatic.Event
      ],
      groups_for_modules: [
        Events: [~r/Packmatic\.Event/],
        "Data Structs": [~r/\.Field/],
        "Auxiliary Modules": [Packmatic.Conn, Packmatic.Buffer]
      ]
    ]
  end

  defp package_files do
    ~w(
      lib/packmatic/*
      mix.exs
    )
  end
end
