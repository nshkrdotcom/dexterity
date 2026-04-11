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
      docs: docs()
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
      files: ~w(lib assets mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "README",
      logo: "assets/dexterity.svg",
      extras: [
        "README.md": [title: "Guide"],
        "CHANGELOG.md": [title: "Changelog"],
        "LICENSE": [title: "License"]
      ],
      groups_for_extras: [
        Documentation: ~r/README.md/,
        Maintenance: ~r/CHANGELOG.md|LICENSE/
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
