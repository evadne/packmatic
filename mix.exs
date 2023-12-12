defmodule Packmatic.MixProject do
  use Mix.Project

  def project do
    [
      app: :packmatic,
      version: "1.1.4",
      elixir: "~> 1.15.7",
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
      flags: ~w(error_handling no_opaque race_conditions underspecs unmatched_returns)a,
      list_unused_filters: true
    ]
  end

  defp deps(:dev) do
    [
      {:dialyxir, "~> 1.1.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.24.2", only: :dev, runtime: false}
    ]
  end

  defp deps(:test) do
    [
      {:briefly, "~> 0.5.0", only: :test},
      {:bypass, "~> 2.1.0", only: :test},
      {:mox, "~> 1.0.0", only: :test},
      {:teamcity_formatter, github: "prook/teamcity_formatter", only: :test, runtime: false},
      {:timex, "~> 3.7.5", only: :test},
      {:stream_data, "~> 0.5.0", only: :test}
    ]
  end

  defp deps(:prod) do
    [
      # {:httpotion, "~> 3.1.3"},
      # {:ibrowse, "4.4.0"},
      {:ssl_verify_fun, "~> 1.1.7"},
      {:httpotion, "~> 3.2.0"},
      {:ibrowse, "~> 4.4.2", override: true},
      {:plug, "~> 1.14", optional: true}
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
        Packmatic.Field,
        Packmatic.Event
      ],
      groups_for_modules: [
        Events: [~r/Packmatic\.Event/],
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
