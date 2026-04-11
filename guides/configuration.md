# Configuration

Dexterity reads its runtime settings from the application environment for `:dexterity`.
Defaults are defined in `Dexterity.Config` and can be overridden in `config/runtime.exs` or before any task/API call.

## Core values

- `:repo_root` — root directory for index/db resolution.
- `:dexter_db` — index filename used by Dexter backend (`.dexter.db`).
- `:store_path` — metadata DB path; defaults to `{:project_relative, ".dexterity/dexterity.db"}`.
- `:dexter_bin` — executable name/path for `dexter`.
- `:backend` — backend module implementing `Dexterity.Backend`.
- `:pagerank_iterations` — rank convergence iterations (default `20`).
- `:pagerank_damping` — damping factor (default `0.85`).
- `:pagerank_context_boost` — context weight for `active_file`/`mentioned_file`/`edited_file`.
- `:default_token_budget` / `:min_token_budget` / `:max_token_budget`.
- `:include_clones` — include deterministic clone annotations.
- `:cochange_commit_depth` / `:cochange_min_frequency` / `:cochange_interval_ms`.
- `:cochange_enabled` — enable temporal worker.
- `:summary_enabled` — enable async semantic summary generation.
- `:summary_signature_threshold` — currently reserved for future signature-based invalidation policy.
- `:clone_similarity_threshold` — reserve for future clone heuristic.
- `:mcp_enabled` — feature-gate for serving MCP.

## Safe operational settings

- Development default assumes short loops:
  - `:cochange_interval_ms` and watchers remain low to keep tests stable.
- Production defaults should preserve back-pressure:
  - Keep `:cochange_commit_depth` bounded.
  - Keep `:min_token_budget` above your model floor.
- If using generated CI containers, keep `:dexter_db` path writable per repo.

## Runtime override examples

```elixir
config :dexterity,
  repo_root: "/workspace/my_app",
  dexter_db: ".custom.dexter.db",
  token_budget: 12_288,
  include_clones: true,
  cochange_enabled: true,
  mcp_enabled: true
```

## Configuration diagnostics

- `mix dexterity.status` returns runtime index/backend/graph health snapshot from these settings.
- Any invalid backend module or missing DB path returns explicit errors that should not be ignored.
