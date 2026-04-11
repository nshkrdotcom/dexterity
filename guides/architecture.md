# Architecture

## Runtime architecture

- The application supervision tree starts:
  - `StoreServer` for metadata DB lifecycle.
  - `IndexSupervisor` with `Indexer` + `FileWatcher`.
  - `GraphServer` for graph/rank state.
  - `CochangeWorker` for temporal coupling.
  - `SummaryWorker` for optional summary cache updates.

## Data and control path

1. Backend reads `.dexter.db` for semantic edges and symbol exports.
2. `GraphServer` builds a ranked adjacency map:
   - base edges from backend
   - source-derived metadata edges from `use`, `@behaviour`, and `defimpl`
   - temporal edges from `Store`
3. Internal source-analysis code parses tracked files for render annotations, clone tokens, and summary inputs.
4. Context inputs (`active_file`, `mentioned_files`, `edited_files`) are applied as query context.
5. `Dexterity` fetches symbols, validates cached summaries by mtime/signature, persists clone signatures, and renders deterministic map text.
5. Mix tasks and MCP call the same public API modules.

## Build boundaries

- Backends are injected via `Dexterity.Backend` callbacks.
- Graph rebuild is lazy and triggered when stale state is detected.
- Metadata persistence happens in local SQLite metadata store (`Store`).
- Clone signatures are cached in `token_signatures`; summary freshness is checked against stored signature + file mtime.
- MCP runs as an explicit transport layer over the same public functions.

## Stability points

- Backend missing DB returns explicit status values.
- Missing graph state does not produce guessed output.
- Ranking and renderer operate in deterministic order.
- Summary worker failures do not block ranking reads.
- Metadata enrichment falls back to base graph behavior when a source file is missing or unreadable.
