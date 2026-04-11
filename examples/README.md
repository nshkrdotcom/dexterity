# Examples

Dexterity ships with runnable examples intended to shorten the time from install to first useful output.

## Included Example

### `comprehensive_real_backend.exs`

Run it with:

```bash
mix run examples/comprehensive_real_backend.exs
```

This example is intentionally real. It requires a working `dexter` binary on `PATH` or a `DEXTER_BIN` environment variable. It:

- creates a temporary Elixir-shaped repo on disk
- initializes a real git repository with multiple commits
- runs `mix dexterity.index` to build or refresh a real `.dexter.db`
- starts Dexterity with `Dexterity.Backend.Dexter`
- lets the real cochange worker ingest git history
- exercises the mix-task surface in-process, including symbol search, file matching, blast-count lookup, and export analysis
- exercises the main public APIs, including term-aware ranking, adaptive auto budgets, impact queries, and dead-code style export analysis
- sends live JSON-RPC requests through the MCP transport layer for the same runtime surface

Use it to validate your local Dexter + Dexterity setup against a disposable repo before pointing Dexterity at a larger project.

## Real Backend Checklist

When you switch from the example backend to `Dexterity.Backend.Dexter`, make sure the target machine has:

1. `dexter` installed and available on `PATH`, or configure `:dexter_bin`.
2. A Dexter index database for the repo, usually `.dexter.db`.
3. `git` installed if you want cochange data from history.

Typical startup flow:

```bash
mix deps.get
mix dexterity.index --repo-root .
mix dexterity.status --repo-root .
mix dexterity.map --repo-root . --active-file lib/my_app.ex
```
