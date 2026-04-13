# Examples

Dexterity ships with runnable examples intended to shorten the time from install to first useful output.

## Included Examples

### `ranked_files_surface.exs`

Run it with:

```bash
mix run examples/ranked_files_surface.exs
```

This is the focused ranked-files example. It uses a deterministic in-script backend to show the exact public surface for:

- raw ranked files, where `deps/` can dominate the result
- first-party filtering through `Dexterity.get_ranked_files/1`
- the matching `mix dexterity.query ranked_files` flags
- the matching MCP `get_ranked_files` arguments

Start here if you want to validate the first-party filtering contract without depending on an external `dexter` binary.

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
- imports real OTP `:cover` observations for a compiled runtime probe module
- exercises the mix-task surface in-process, including first-party ranked-file selection, structural snapshot export, symbol search, file matching, blast-count lookup, and callback-aware export analysis
- exercises the main public APIs, including first-party ranked-file selection, file/symbol graph snapshots, term-aware ranking, symbol ranking, adaptive impact context, callback-aware export analysis, runtime observations, and runtime confirmation
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
