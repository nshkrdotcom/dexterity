# Quick Start

## Installation

Add the package in your project `mix.exs`:

```elixir
defp deps do
  [
    {:dexterity, "~> 0.1.0"}
  ]
end
```

## Minimum runtime

1. Ensure `dexter` binary is on `PATH` or set `dexter_bin`.
2. Ensure `.dexter.db` exists (or allow `dexterity.index` task to build it).
3. Start the app so OTP supervision is active.

## Basic usage

```elixir
{:ok, map} = Dexterity.get_repo_map(active_file: "lib/my_app.ex", token_budget: 2048)
{:ok, ranked} = Dexterity.get_ranked_files(limit: 20)
{:ok, refs} = Dexterity.Query.find_references("MyApp.Accounts", "register", 2)
```

## Notes

- No silent fallback for core failures.
- Missing dexter index should flow through status/error semantics, not guesswork.
- Token budget is capped: results always respect configured limit.
