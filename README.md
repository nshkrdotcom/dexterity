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
- It exports normalized file and symbol graph snapshots for downstream consumers.
- It renders a token-budgeted repo map for agent prompts.
- It exposes semantic queries and an optional stdio MCP server.

If you want exact, repeatable codebase context instead of ad hoc grep output, this is the layer Dexterity provides.

Dexterity is also the right structural kernel to build on if you plan to add a separate semantic retrieval library or a higher-level code intelligence platform later. The graph, snapshot, impact, and runtime surfaces are meant to be consumed directly without reaching into internal servers.

## What You Get

- `Dexterity.get_repo_map/1` for ranked, prompt-ready repository context.
- `Dexterity.get_ranked_files/1` with active-file, edit, and conversation-term ranking inputs.
- `Dexterity.get_ranked_symbols/1` for symbol-level ranking over the same repo state.
- `Dexterity.get_impact_context/1` for adaptive, diff-aware symbol context.
- `Dexterity.get_file_graph_snapshot/1`, `Dexterity.get_symbol_graph_snapshot/1`, and `Dexterity.get_structural_snapshot/1` for stable structural exports.
- `Dexterity.get_symbols/2`, `Dexterity.find_symbols/2`, and `Dexterity.match_files/2` for targeted discovery.
- `Dexterity.get_module_deps/2` and `Dexterity.get_file_blast_radius/2` for impact checks.
- `Dexterity.get_export_analysis/1`, `Dexterity.get_unused_exports/1`, and `Dexterity.get_test_only_exports/1` for callback-aware export analysis.
- `Dexterity.get_runtime_observations/1`, `Dexterity.record_runtime_observations/2`, and `Dexterity.import_cover_modules/2` for persisted runtime confirmation.
- `Dexterity.Query` for definitions, references, blast radius, and cochange neighbors.
- Mix tasks for indexing, status, map rendering, and query execution.
- Optional MCP transport over stdio for editor and agent integrations.

## Requirements

Dexterity itself is pure Elixir, but the default production backend depends on external tooling:

1. `dexter` CLI must be installed and available on `PATH`, or configured via `:dexter_bin`.
2. A Dexter index database must exist for the target repo, usually `.dexter.db`.
3. `git` should be available if you want cochange analysis to be useful.
4. Native build tooling required by `exqlite` must be available on the machine building dependencies.
5. If you want cover-backed runtime confirmation, the OTP `tools` install and debug-info beams must be available, plus `elixirc` to build sample modules in the example flow.

The included example is fully real: it creates a temporary repo, builds a real Dexter index through `mix dexterity.index`, ingests real git history for cochanges, imports real OTP `:cover` runtime evidence, and exercises Dexterity's mix tasks, library APIs, and MCP request handling against the resulting `.dexter.db`.

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
mix dexterity.query file_graph --repo-root .
mix dexterity.query symbol_graph --repo-root .
mix dexterity.query runtime_observations --repo-root .
mix dexterity.query structural_snapshot --repo-root . --include-export-analysis --include-runtime-observations
mix dexterity.query ranked_symbols --repo-root . --active-file lib/my_app/accounts.ex
mix dexterity.query impact_context --repo-root . --changed-file lib/my_app/accounts.ex --token-budget 2048
mix dexterity.query export_analysis --repo-root .
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

{:ok, file_graph} =
  Dexterity.get_file_graph_snapshot(
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter
  )

{:ok, symbol_graph} =
  Dexterity.get_symbol_graph_snapshot(
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter
  )

{:ok, ranked_symbols} =
  Dexterity.get_ranked_symbols(
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter,
    active_file: "lib/my_app/accounts.ex",
    mentioned_files: ["lib/my_app_web/live/dashboard_live.ex"],
    limit: 12
  )

{:ok, impact_context} =
  Dexterity.get_impact_context(
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter,
    changed_files: ["lib/my_app/accounts.ex"],
    token_budget: 2048,
    limit: 12
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

{:ok, export_analysis} =
  Dexterity.get_export_analysis(
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter
  )

{:ok, structural_snapshot} =
  Dexterity.get_structural_snapshot(
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter,
    include_export_analysis: true,
    include_runtime_observations: true
  )
```

`Dexterity.get_repo_map/1` is the main file-level integration point for agent context. `get_ranked_symbols/1` and `get_impact_context/1` sit on top of the symbol graph and are the higher-precision surfaces to use when you already know what changed or which file the model is focused on. `get_file_graph_snapshot/1`, `get_symbol_graph_snapshot/1`, and `get_structural_snapshot/1` are the stable kernel exports to use when you are building a sibling semantic indexer or a larger platform on top of Dexterity. `get_export_analysis/1` separates ordinary public API from callback entrypoints and can fold in persisted runtime confirmation from `import_cover_modules/2`.

## MCP Server

Dexterity can also serve the same context surface as a stdio JSON-RPC MCP server:

```bash
mix dexterity.mcp.serve --repo-root .
```

Supported tools include:

- `get_repo_map`
- `get_file_graph_snapshot`
- `get_ranked_files`
- `get_ranked_symbols`
- `get_impact_context`
- `find_symbols`
- `match_files`
- `get_symbols`
- `get_symbol_graph_snapshot`
- `get_structural_snapshot`
- `get_export_analysis`
- `get_runtime_observations`
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
- symbol-level ranking and adaptive impact-context rendering
- normalized file, symbol, and combined structural snapshot export
- semantic symbol and file lookup
- definition and reference queries
- dependency lookup and direct blast radius counts
- cochange enrichment
- callback-aware export analysis and unused/test-only filtered views
- raw runtime observations plus real `:cover` import for runtime-confirmed exports
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
