defmodule Crawly.Mixfile do
  use Mix.Project

  @version "0.10.0"

  def project do
    [
      app: :crawly,
      version: @version,
      name: "Crawly",
      source_url: "https://github.com/oltarasenko/crawly",
      elixir: "~> 1.7",
      description: description(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs(),
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp aliases do
    [
      generate_documentation: &generate_documentation/1
    ]
  end

  defp generate_documentation(_) do
    System.cmd("mix", ["docs"])
    System.cmd("mkdir", ["-p", "./doc/documentation/assets"])
    System.cmd("cp", ["-r", "documentation/assets", "doc/documentation"])
  end

  defp elixirc_paths(:test), do: ["lib", "test"]
  defp elixirc_paths(_), do: ["lib"]
  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :sasl, :httpoison],
      mod: {Crawly.Application, []}
    ]
  end

  defp description() do
    "High-level web crawling & scraping framework for Elixir."
  end

  defp package() do
    [
      # This option is only needed when you don't want to use the OTP application name
      name: "crawly",
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => "https://github.com/oltarasenko/crawly"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 1.4"},
      {:uuid, "~> 1.1"},
      {:poison, "~> 3.1"},
      {:new_gollum, "~> 0.3.0"},
      {:plug_cowboy, "~> 2.0"},
      {:epipe, "~> 1.0"},
      {:faker, "~> 0.14.0"},
      {:credo, "~> 1.0.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:earmark, "~> 1.2", only: :dev},
      {:meck, "~> 0.8.13", only: :test},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      logo: "documentation/assets/logo.png",
      extra_section: "documentation",
      main: "readme",
      formatters: ["html"],
      groups_for_modules: [
        "Building Spiders": [
          Crawly.Response,
          Crawly.Request,
          Crawly.Spider,
          Crawly.ParsedItem
        ],
        "Middlewares and Pipelines": ~r"Crawly\.(Pipeline|Middlewares)(.*)",
        "Under the Hood": [
          Crawly.Engine,
          Crawly.Manager,
          Crawly.Worker,
          Crawly.DataStorage,
          Crawly.DataStorage.Worker,
          Crawly.RequestsStorage,
          Crawly.RequestsStorage.Worker
        ]
      ],
      extras: extras(),
      nest_modules_by_prefix: [
        Crawly.Middlewares,
        Crawly.Pipelines
      ]
    ]
  end

  defp extras do
    [
      "documentation/tutorial.md",
      "documentation/basic_concepts.md",
      "documentation/configuration.md",
      "documentation/http_api.md",
      "documentation/ethical_aspects.md",
      "documentation/experimental_ui.md",
      "readme.md": [title: "Introduction", file: "README.md"]
    ]
  end
end
