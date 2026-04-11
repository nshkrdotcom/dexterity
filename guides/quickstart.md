# Quick Start

## Install

Add the dependency to your host project:

```elixir
def deps do
  [
    {:dexterity, "~> 0.1.0"}
  ]
end
```

## Real Example

If you want to validate the full real backend flow before wiring Dexterity into a larger codebase, run:

```bash
mix run examples/comprehensive_real_backend.exs
```

That example uses a real `dexter` binary, a real temporary `.dexter.db`, and real git history.

## Minimum local runtime

1. Ensure `dexter` CLI is installed and accessible on `PATH`, or set `:dexter_bin`.
2. Ensure the index exists:
   - `mix dexterity.index --repo-root PATH`
3. Start OTP runtime in development (for API usage) or call functions from tests with temporary config.

## Standard flow

```elixir
# Build the map for one request
{:ok, map} = Dexterity.get_repo_map(active_file: "lib/my_app.ex", token_budget: 2048, limit: 20)
{:ok, ranked} = Dexterity.get_ranked_files(limit: 20, repo_root: ".", backend: Dexterity.Backend.Dexter)
{:ok, refs} = Dexterity.Query.find_references("MyApp.Accounts", "register", 2, backend: Dexterity.Backend.Dexter)
```

## Mix task usage

```bash
mix dexterity.index --repo-root .
mix dexterity.status --repo-root .
mix dexterity.map --active-file lib/my_app.ex --limit 20 --token-budget 2048
mix dexterity.query references MyApp.Accounts register 2
```

## Error handling posture

- No silent fallbacks for required data.
- Missing index and degraded backends must return explicit tuples.
- Ranking and rendering are deterministic for fixed inputs.
