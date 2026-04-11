defmodule Dexterity.MixProject do
  use Mix.Project

  @version "0.1.0"
  @repo_url "https://github.com/nshkrdotcom/dexterity"

  def project do
    [
      app: :dexterity,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Dexterity",
      source_url: @repo_url,
      homepage_url: @repo_url,
      docs: docs(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Dexterity.Application, []}
    ]
  end

  defp description do
    "Authoritative, ranked, token-budgeted codebase context for Elixir agents."
  end

  defp package do
    [
      name: "dexterity",
      licenses: ["MIT"],
      links: %{"GitHub" => @repo_url},
      files: ~w(lib assets examples mix.exs README.md LICENSE CHANGELOG.md guides)
    ]
  end

  defp deps do
    [
      {:exqlite, "~> 0.28"},
      {:file_system, "~> 1.0"},
      {:nx, "~> 0.9", optional: true},
      {:tiktoken, "~> 0.4", optional: true},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :missing_return, :underspecs]
    ]
  end

  defp docs do
    [
      main: "guide",
      logo: "assets/dexterity.svg",
      extras: [
        "README.md": [filename: "guide", title: "Guide"],
        "examples/README.md": [filename: "examples", title: "Examples"],
        "guides/overview.md": [title: "Overview"],
        "guides/quickstart.md": [title: "Quickstart"],
        "guides/architecture.md": [title: "Architecture"],
        "guides/kernel_surfaces.md": [title: "Kernel Surfaces"],
        "guides/api_reference.md": [title: "API Reference"],
        "guides/configuration.md": [title: "Configuration"],
        "guides/mcp.md": [title: "MCP Server"],
        "guides/mix_tasks.md": [title: "Mix Tasks"],
        "guides/testing_and_quality.md": [title: "Testing + Quality"],
        "guides/operations.md": [title: "Operations"],
        "guides/buildout_playbook.md": [title: "Buildout Playbook"],
        "guides/roadmap.md": [title: "Roadmap"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        "Dexterity Guide": ~r/README.md/,
        Examples: ~r/^examples\//,
        "Developer Guides": ~r/^guides\//,
        Maintenance: ~r/CHANGELOG.md|LICENSE/
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
