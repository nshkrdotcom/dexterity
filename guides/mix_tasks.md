# Mix Tasks

Dexterity publishes its CLI commands through `mix` tasks.

## Available tasks

### `mix dexterity.index`

- `--repo-root PATH` (default config repo root)
- `--backend MODULE` (default `Dexterity.Backend.Dexter`)

Creates a missing Dexter index with `backend.cold_index/2`, or refreshes an existing one with `backend.reindex_file/2`, then outputs `index refreshed` on success.

### `mix dexterity.status`

- `--repo-root PATH`
- `--backend MODULE`

Prints a normalized status map with backend and graph health.

### `mix dexterity.map`

- `--active-file FILE`
- `--mentioned-file FILE` (repeatable)
- `--edited-file FILE` (repeatable)
- `--limit N` (default `25`)
- `--token-budget N|auto`
- `--include-clones` / `--no-include-clones`
- `--repo-root PATH`
- `--backend MODULE`
- `--output PATH`

Renders map text to stdout or writes to file.

### `mix dexterity.query`

- `references MODULE [FUNCTION] [ARITY]`
- `definition MODULE [FUNCTION] [ARITY]`
- `blast FILE [--depth N]`
- `blast_count FILE`
- `cochanges FILE [--limit N]`
- `symbols QUERY [--limit N]`
- `files SQL_LIKE_PATTERN [--limit N]`
- `ranked_symbols [--active-file FILE] [--mentioned-file FILE] [--limit N]`
- `impact_context [--changed-file FILE] [--token-budget N] [--limit N]`
- `export_analysis [--limit N]`
- `unused_exports [--limit N]`
- `test_only_exports`

`depth` defaults to `2`; `limit` defaults to `25`.

### `mix dexterity.mcp.serve`

- `--repo-root PATH`
- `--backend MODULE`

Starts the production MCP stdio transport.

## Task behavior rules

- All tasks validate positional arguments and terminate with `Mix.Error` on invalid input.
- CLI tasks are deterministic for equivalent option sets.
- Failures return surfaced error payloads with one user-facing summary line.
