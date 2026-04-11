# Configuration Guide

Configuration keys currently supported by `Dexterity.Config`:

- `:repo_root`
- `:dexter_db`
- `:store_path`
- `:dexter_bin`
- `:backend`
- `:pagerank_iterations`
- `:pagerank_damping`
- `:pagerank_uniform_baseline`
- `:pagerank_context_boost`
- `:default_token_budget`
- `:min_token_budget`
- `:max_token_budget`
- `:token_budget_saturation_tokens`
- `:include_clones`
- `:min_rank`
- `:cochange_commit_depth`
- `:cochange_min_frequency`
- `:cochange_interval_ms`
- `:cochange_enabled`
- `:watch_debounce_ms`
- `:summary_enabled`
- `:summary_signature_threshold`
- `:clone_similarity_threshold`
- `:token_model`
- `:mcp_enabled`

## Recommended defaults

- Keep defaults in `lib/dexterity/config.ex`.
- Override per environment through `config/*.exs`.
- `:backend` should default to `Dexterity.Backend.Dexter`.
- `:summary_enabled` should remain false until provider integration is proven in tests.
