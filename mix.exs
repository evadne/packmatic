defmodule Packmatic.MixProject do
  use Mix.Project

  def project do
    [
      app: :packmatic,
      version: "1.0.0",
      elixir: "~> 1.9",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
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
      flags: ~w(error_handling no_opaque race_conditions underspecs unmatched_returns)a,
      ignore_warnings: "dialyzer-ignore-warnings.exs",
      list_unused_filters: true
    ]
  end

  defp deps do
    [
      {:briefly, "~> 0.3.0", only: :test},
      {:bypass, "~> 1.0.0", only: :test},
      {:dialyxir, "~> 1.0.0-rc.6", only: :dev, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:httpotion, "~> 3.1.2"},
      {:ibrowse, "~> 4.4.0"},
      {:teamcity_formatter, github: "prook/teamcity_formatter", only: [:test], runtime: false},
      {:timex, "~> 3.6.1", only: :test}
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
        Packmatic.Field
      ],
      groups_for_modules: [
        "Data Structs": [~r/\.Field/],
        Helpers: [Packmatic.Conn]
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
