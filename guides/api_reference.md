# API Reference

Authoritative public API behavior for Dexterity.

## Core API (`Dexterity`)

- `get_repo_map(context_opts) :: {:ok, String.t()} | {:error, term()}`
- `get_ranked_files(context_opts) :: {:ok, [{String.t(), float()}]} | {:error, term()}`
- `get_symbols(file, opts \\\\ []) :: {:ok, [map()]} | {:error, :not_indexed} | {:error, term()}`
- `get_module_deps(file, opts \\\\ []) :: {:ok, %{dependencies: [String.t()], dependents: [String.t()]}} | {:error, :graph_unavailable | term()}`
- `notify_file_changed(file, opts \\\\ []) :: :ok | {:error, term()}`
- `status() :: {:ok, status_snapshot()} | {:error, term()}`

`status_snapshot()` includes:
- `:backend`
- `:dexter_db`
- `:index_status`
- `:backend_healthy`
- `:graph_stale`
- `:files`

## Query API (`Dexterity.Query`)

- `find_references(module, function \\\\ nil, arity \\\\ nil, opts \\\\ []) :: {:ok, [reference_location()]} | {:error, term()}`
- `find_definition(module, function \\\\ nil, arity \\\\ nil, opts \\\\ []) :: {:ok, [symbol()]} | {:error, :not_found} | {:error, term()}`
- `blast_radius(file, opts \\\\ []) :: {:ok, [blast_result()]} | {:error, term()}`
- `cochanges(file, limit \\ 10, opts \\\\ []) :: {:ok, [{String.t(), float()}]} | {:error, term()}`

`Query` opts support:
- `:backend`
- `:repo_root`
- `:graph_server`
- `:depth`
- `:limit`

## Graph API (`Dexterity.Graph`)

- `get_adjacency(opts \\\\ []) :: {:ok, adjacency()} | {:error, term()}`
- `pagerank(context_files, opts \\\\ []) :: {:ok, [{String.t(), float()}]} | {:error, term()}`
- `baseline(opts \\\\ []) :: {:ok, %{String.t() => float()}} | {:error, term()}`

`get_adjacency/1`, `pagerank/2`, and `baseline/1` accept `:server` for alternate graph processes.

## Mix task surface

- `mix dexterity.index [--repo-root PATH] [--backend MODULE]`
- `mix dexterity.status [--repo-root PATH] [--backend MODULE]`
- `mix dexterity.map`
  - `--active-file FILE`
  - `--mentioned-file FILE`
  - `--edited-file FILE`
  - `--limit N`
  - `--token-budget N|auto`
  - `--include-clones true|false`
  - `--output PATH`
  - `--backend MODULE`
- `mix dexterity.query references|definition|blast|cochanges [args]`
- `mix dexterity.mcp.serve --repo-root PATH` (production transport)

## Error and stability contract

- Explicit error tuples are preferred over silent fallback.
- Ranking and rendering are deterministic for fixed inputs.
- Token budgeting in `get_repo_map/1` is bounded by config.
- MCP responses include `jsonrpc` and `error` payloads for non-recoverable calls.
