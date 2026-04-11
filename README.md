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
- `Dexterity.get_symbols/2` and `Dexterity.get_module_deps/2` for targeted lookups.
- `Dexterity.Query` for definitions, references, blast radius, and cochange neighbors.
- Mix tasks for indexing, status, map rendering, and query execution.
- Optional MCP transport over stdio for editor and agent integrations.

## Requirements

Dexterity itself is pure Elixir, but the default production backend depends on external tooling:

1. `dexter` CLI must be installed and available on `PATH`, or configured via `:dexter_bin`.
2. A Dexter index database must exist for the target repo, usually `.dexter.db`.
3. `git` should be available if you want cochange analysis to be useful.
4. Native build tooling required by `exqlite` must be available on the machine building dependencies.

The included example is fully real: it creates a temporary repo, builds a real Dexter index, ingests real git history for cochanges, and runs Dexterity against the resulting `.dexter.db`.

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

Build the Dexter index for the repo:

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
mix dexterity.query cochanges lib/my_app/accounts.ex --repo-root . --limit 10
```

## Using The Library In Code

```elixir
{:ok, repo_map} =
  Dexterity.get_repo_map(
    repo_root: "/workspace/my_app",
    backend: Dexterity.Backend.Dexter,
    active_file: "lib/my_app/accounts.ex",
    mentioned_files: ["lib/my_app_web/live/dashboard_live.ex"],
    token_budget: 4096,
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
```

`Dexterity.get_repo_map/1` is the main integration point for agent context. The other APIs are useful when you want deterministic follow-up queries after a model identifies a symbol or file of interest.

## MCP Server

Dexterity can also serve the same context surface as a stdio JSON-RPC MCP server:

```bash
mix dexterity.mcp.serve --repo-root .
```

Supported tools include:

- `get_repo_map`
- `get_ranked_files`
- `get_symbols`
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

- real Dexter indexing
- real git-driven cochange ingestion
- ranked repo map generation
- semantic symbol lookup
- definition and reference queries
- dependency lookup
- blast radius
- cochange enrichment
- real file reindexing

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
