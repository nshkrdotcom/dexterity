# API Reference

Authoritative public API behavior for Dexterity.

## Core API (`Dexterity`)

- `get_repo_map(context_opts) :: {:ok, String.t()} | {:error, term()}`
- `get_ranked_files(context_opts) :: {:ok, [{String.t(), float()}]} | {:error, term()}`
- `get_ranked_symbols(context_opts) :: {:ok, [map()]} | {:error, term()}`
- `get_impact_context(context_opts) :: {:ok, String.t()} | {:error, term()}`
- `get_file_graph_snapshot(opts \\\\ []) :: {:ok, Dexterity.FileGraphSnapshot.t()} | {:error, term()}`
- `get_symbol_graph_snapshot(opts \\\\ []) :: {:ok, Dexterity.SymbolGraphSnapshot.t()} | {:error, term()}`
- `get_structural_snapshot(opts \\\\ []) :: {:ok, Dexterity.StructuralSnapshot.t()} | {:error, term()}`
- `get_symbols(file, opts \\\\ []) :: {:ok, [map()]} | {:error, :not_indexed} | {:error, term()}`
- `find_symbols(query, opts \\\\ []) :: {:ok, [ranked_symbol()]} | {:error, term()}`
- `match_files(sql_like_pattern, opts \\\\ []) :: {:ok, [String.t()]} | {:error, term()}`
- `get_module_deps(file, opts \\\\ []) :: {:ok, %{dependencies: [String.t()], dependents: [String.t()]}} | {:error, :graph_unavailable | term()}`
- `get_file_blast_radius(file, opts \\\\ []) :: {:ok, non_neg_integer()} | {:error, term()}`
- `get_export_analysis(opts \\\\ []) :: {:ok, [export_analysis()]} | {:error, term()}`
- `get_unused_exports(opts \\\\ []) :: {:ok, [unused_export()]} | {:error, term()}`
- `get_test_only_exports(opts \\\\ []) :: {:ok, [map()]} | {:error, term()}`
- `get_runtime_observations(opts \\\\ []) :: {:ok, [runtime_observation()]} | {:error, term()}`
- `record_runtime_observations(observations, opts \\\\ []) :: {:ok, non_neg_integer()} | {:error, term()}`
- `import_cover_modules(modules, opts \\\\ []) :: {:ok, non_neg_integer()} | {:error, term()}`
- `notify_file_changed(file, opts \\\\ []) :: :ok | {:error, term()}`
- `status() :: {:ok, status_snapshot()} | {:error, term()}`

`status_snapshot()` includes:
- `:backend`
- `:dexter_db`
- `:index_status`
- `:backend_healthy`
- `:graph_stale`
- `:files`

`context_opts` may also include:
- `:conversation_terms`
- `:conversation_tokens`
- `:changed_files`
- `:changed_symbols`
- `:graph_server`
- `:symbol_graph_server`
- `:summary_server`
- `:store_conn`
- `:summary_enabled`

`export_analysis()` includes:
- `:kind` (`:public_api` or `:callback_entrypoint`)
- `:reachability` (`:production`, `:callback`, `:runtime`, `:test_only`, `:internal_only`, `:unused`)
- `:entrypoint_sources`
- `:runtime_call_count`
- `:runtime_sources`
- explicit ref counts and `:used_internally`

`Dexterity.FileGraphSnapshot.t()` includes:
- `:repo_root`
- `:backend`
- `:files`
- `:edges`
- `:generated_at`
- `:fingerprint`

`Dexterity.SymbolGraphSnapshot.t()` includes:
- `:repo_root`
- `:backend`
- `:nodes`
- `:edges`
- `:source_snippets`
- `:generated_at`
- `:fingerprint`

`Dexterity.StructuralSnapshot.t()` includes:
- `:file_graph`
- `:symbol_graph`
- optional `:export_analysis`
- optional `:runtime_observations`
- `:generated_at`
- `:fingerprint`

## Query API (`Dexterity.Query`)

- `find_references(module, function \\\\ nil, arity \\\\ nil, opts \\\\ []) :: {:ok, [reference_location()]} | {:error, term()}`
- `find_definition(module, function \\\\ nil, arity \\\\ nil, opts \\\\ []) :: {:ok, [symbol()]} | {:error, :not_found} | {:error, term()}`
- `blast_radius(file, opts \\\\ []) :: {:ok, [blast_result()]} | {:error, term()}`
- `cochanges(file, limit \\ 10, opts \\\\ []) :: {:ok, [{String.t(), float()}]} | {:error, term()}`

`Query` opts support:
- `:backend`
- `:repo_root`
- `:graph_server`
- `:store_conn`
- `:store_server`
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
  - `--include-clones` / `--no-include-clones`
  - `--output PATH`
  - `--backend MODULE`
- `mix dexterity.query references|definition|blast|cochanges [args]`
- `mix dexterity.query blast_count|symbols|files|file_graph|symbol_graph|structural_snapshot|runtime_observations|ranked_symbols|impact_context|export_analysis|unused_exports|test_only_exports [args]`
- `mix dexterity.mcp.serve --repo-root PATH` (production transport)

## Error and stability contract

- Explicit error tuples are preferred over silent fallback.
- Ranking and rendering are deterministic for fixed inputs.
- Token budgeting in `get_repo_map/1` is bounded by config.
- `token_budget: :auto` adapts to `:conversation_tokens` while respecting config min/max bounds.
- Conversation terms can raise the rank of files whose path or source tokens match the current discussion.
- File-graph consumers can request snapshots without depending on an already-running matching `GraphServer`; Dexterity can build a deterministic temporary file graph for that request.
- Symbol ranking uses a separate symbol graph and can spin up a deterministic temporary symbol-graph server when the caller provides a backend/repo pair without a running symbol graph process.
- Structural snapshots expose deterministic fingerprints so downstream layers can decide when to rebuild their own derived indices.
- Impact context is symbol-oriented and adapts detail level to the token budget instead of rendering whole files only.
- Export analysis is callback-aware and does not rely only on explicit static references.
- Runtime confirmation is optional and additive; when no runtime evidence exists, the report falls back to static analysis plus entrypoint inference.
- Summary reads are cache-backed and only rendered when stored signature and file mtime are current.
- Clone annotations are deterministic and suppress duplicate symbol bodies for lower-ranked matches.
- MCP responses include `jsonrpc` and `error` payloads for non-recoverable calls.
