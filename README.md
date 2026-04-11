# Dexterity

<p align="center">
  <img src="assets/dexterity.svg" alt="Dexterity Logo" width="200" height="200">
</p>

<p align="center">
  Ranked, deterministic repository context for Elixir tooling, agents, and MCP clients.
</p>

Dexterity turns an Elixir codebase into a queryable context layer:

- It reads semantic edges from a Dexter-produced `.dexter.db`.
- It builds a ranked repository graph with metadata-derived links.
- It renders a token-budgeted repo map for agent prompts.
- It exposes semantic queries and an optional stdio MCP server.

If you want exact, repeatable codebase context instead of ad hoc grep output, this is the layer Dexterity provides.

## What You Get

- `Dexterity.get_repo_map/1` for ranked, prompt-ready repository context.
- `Dexterity.get_ranked_files/1` with active-file, edit, and conversation-term ranking inputs.
- `Dexterity.get_symbols/2`, `Dexterity.find_symbols/2`, and `Dexterity.match_files/2` for targeted discovery.
- `Dexterity.get_module_deps/2` and `Dexterity.get_file_blast_radius/2` for impact checks.
- `Dexterity.get_unused_exports/1` and `Dexterity.get_test_only_exports/1` for dead-code style export analysis.
- `Dexterity.Query` for definitions, references, blast radius, and cochange neighbors.
- Mix tasks for indexing, status, map rendering, and query execution.
- Optional MCP transport over stdio for editor and agent integrations.

## Requirements

Dexterity itself is pure Elixir, but the default production backend depends on external tooling:

1. `dexter` CLI must be installed and available on `PATH`, or configured via `:dexter_bin`.
2. A Dexter index database must exist for the target repo, usually `.dexter.db`.
3. `git` should be available if you want cochange analysis to be useful.
4. Native build tooling required by `exqlite` must be available on the machine building dependencies.

The included example is fully real: it creates a temporary repo, builds a real Dexter index through `mix dexterity.index`, ingests real git history for cochanges, and exercises Dexterity's mix tasks, library APIs, and MCP request handling against the resulting `.dexter.db`.

## Installation

Add Dexterity to your dependencies:

```elixir
defp deps do
  [
    {:dexterity, "~> 0.1.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## First Run With The Real Dexter Backend

Configure the runtime:

```elixir
# config/runtime.exs
config :dexterity,
  repo_root: System.get_env("PROJECT_ROOT") || File.cwd!(),
  backend: Dexterity.Backend.Dexter,
  dexter_bin: System.get_env("DEXTER_BIN") || "dexter",
  dexter_db: ".dexter.db",
  mcp_enabled: true
```

Build or refresh the Dexter index for the repo:

```bash
mix dexterity.index --repo-root .
```

Verify the backend and graph state:

```bash
mix dexterity.status --repo-root .
```

Generate a prompt-ready repo map:

```bash
mix dexterity.map \
  --repo-root . \
  --active-file lib/my_app/accounts.ex \
  --mentioned-file lib/my_app_web/live/dashboard_live.ex \
  --limit 20 \
  --token-budget 4096
```

Run semantic queries:

```bash
mix dexterity.query definition MyApp.Accounts register 2 --repo-root .
mix dexterity.query references MyApp.Accounts register 2 --repo-root .
mix dexterity.query blast lib/my_app/accounts.ex --repo-root . --depth 2
mix dexterity.query blast_count lib/my_app/accounts.ex --repo-root .
mix dexterity.query cochanges lib/my_app/accounts.ex --repo-root . --limit 10
mix dexterity.query symbols refund --repo-root .
mix dexterity.query files '%accounts%' --repo-root .
mix dexterity.query unused_exports --repo-root .
mix dexterity.query test_only_exports --repo-root .
```

## Using The Library In Code

```elixir
{:ok, repo_map} =
  Dexterity.get_repo_map(
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter,
    active_file: "lib/my_app/accounts.ex",
    mentioned_files: ["lib/my_app_web/live/dashboard_live.ex"],
    conversation_terms: ["refund"],
    conversation_tokens: 120_000,
    token_budget: :auto,
    limit: 20
  )

{:ok, symbols} =
  Dexterity.get_symbols(
    "lib/my_app/accounts.ex",
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter
  )

{:ok, references} =
  Dexterity.Query.find_references(
    "MyApp.Accounts",
    "register",
    2,
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter
  )

{:ok, ranked_symbol_hits} =
  Dexterity.find_symbols(
    "refund",
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter
  )

{:ok, indexed_account_files} =
  Dexterity.match_files(
    "%accounts%",
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter
  )

{:ok, blast_count} =
  Dexterity.get_file_blast_radius(
    "lib/my_app/accounts.ex",
    repo_root: "/workspace/my_app"
  )

{:ok, unused_exports} =
  Dexterity.get_unused_exports(
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter
  )
```

`Dexterity.get_repo_map/1` is the main integration point for agent context. The search and analysis APIs are useful when you want deterministic follow-up queries after a model identifies a symbol or file of interest.

## MCP Server

Dexterity can also serve the same context surface as a stdio JSON-RPC MCP server:

```bash
mix dexterity.mcp.serve --repo-root .
```

Supported tools include:

- `get_repo_map`
- `get_ranked_files`
- `find_symbols`
- `match_files`
- `get_symbols`
- `get_file_blast_radius`
- `get_unused_exports`
- `get_test_only_exports`
- `get_module_deps`
- `query_definition`
- `query_references`
- `query_blast`
- `query_cochanges`
- `status`

## Examples

Start with the runnable example:

```bash
mix run examples/comprehensive_real_backend.exs
```

That example shows:

- real Dexter indexing through `mix dexterity.index`
- live mix-task status, map, and query execution
- real git-driven cochange ingestion
- ranked repo map generation with adaptive auto budgeting and conversation-term boosts
- semantic symbol and file lookup
- definition and reference queries
- dependency lookup and direct blast radius counts
- cochange enrichment
- unused-export and test-only-export analysis
- real file reindexing
- live MCP JSON-RPC requests

See [examples/README.md](examples/README.md) for details.

## Operational Notes

- Dexterity does not compile or evaluate project code to build context.
- The real backend is only as fresh as the underlying Dexter index.
- Summary generation is opt-in and disabled by default.
- Cochange data is additive; if `git` history is unavailable, ranking still works from semantic and metadata edges.

## Documentation

- Start with [Quickstart](guides/quickstart.md) and [Configuration](guides/configuration.md).
- Runnable example documentation lives in [examples/README.md](examples/README.md).
- HexDocs is configured from this repository via `mix docs`.

## License

MIT. See [LICENSE](LICENSE).
