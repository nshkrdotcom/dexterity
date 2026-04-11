<p align="center">
  <img src="assets/dexterity.svg" alt="Dexterity Logo" width="200" height="200">
</p>

<h1 align="center">Dexterity</h1>

<p align="center">
  <a href="https://github.com/nshkrdotcom/dexterity">
    <img src="https://img.shields.io/badge/github-nshkrdotcom/dexterity-181717?logo=github&style=flat-square" alt="GitHub">
[![SafeSkill 93/100](https://img.shields.io/badge/SafeSkill-93%2F100_Verified%20Safe-brightgreen)](https://safeskill.dev/scan/nshkrdotcom-dexterity)
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License">
  </a>
</p>

---

**Dexterity** is a pure Elixir library and optional MCP server that provides LLM agents and AI coding tools with authoritative, ranked, token-budgeted codebase context for Elixir projects.

It solves the specific failure mode of current AI coding tools against macro-heavy Elixir monorepos by providing a deterministic, exact Elixir semantic graph combined with a dynamic, agent-ready "Repo Map."

## Key Features

- **Ground Truth Layer:** Deterministic Elixir semantic graph maintained by the Dexter CLI indexer.
- **Intelligence Layer:** Personalized PageRank engine, git temporal coupling analysis, and semantic summary caching.
- **Token-Budgeted Rendering:** BPE-bounded output guaranteed to fit within agent context limits.
- **Zero Compiler Dependency:** Works on broken, partial, and syntax-errored code.
- **OTP Idiomatic:** Built as a native Elixir/OTP application.

## Installation

The package can be installed by adding `dexterity` to your list of dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:dexterity, "~> 0.1.0"}
  ]
end
```

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc) and published on [HexDocs](https://hexdocs.pm). Once published, the docs can be found at [https://hexdocs.pm/dexterity](https://hexdocs.pm/dexterity).

---
© 2026 nshkrdotcom
