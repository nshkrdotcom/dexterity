# Examples

Dexterity ships with runnable examples intended to shorten the time from install to first useful output.

## Included Example

### `comprehensive_mock_backend.exs`

Run it with:

```bash
mix run examples/comprehensive_mock_backend.exs
```

This example is intentionally self-contained. It does not require a real `dexter` binary or a `.dexter.db` file. Instead, it:

- creates a temporary Elixir-shaped repo on disk
- starts a temporary SQLite metadata store
- uses a stub backend that implements `Dexterity.Backend`
- injects cochange data
- starts `Dexterity.GraphServer`
- starts `Dexterity.SummaryWorker`
- exercises the main public APIs and prints the results

Use it to learn the API shape before wiring Dexterity to a real indexed repository.

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
