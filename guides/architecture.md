# Architecture

## Runtime architecture

- The application supervision tree starts:
  - `StoreServer` for metadata DB lifecycle.
  - `IndexSupervisor` with `Indexer` + `FileWatcher`.
  - `GraphServer` for graph/rank state.
  - `SymbolGraphServer` for symbol graph/rank state.
  - `CochangeWorker` for temporal coupling.
  - `SummaryWorker` for optional summary cache updates.

## Data and control path

1. Backend reads `.dexter.db` for semantic edges and symbol exports.
2. `GraphServer` builds a ranked adjacency map:
   - base edges from backend
   - source-derived metadata edges from `use`, `@behaviour`, and `defimpl`
   - temporal edges from `Store`
3. `SymbolGraphServer` builds a separate function/symbol graph from backend symbol nodes and symbol call edges, with a deterministic fallback path when only definitions/references are available.
4. Internal source-analysis code parses tracked files for render annotations, symbol signatures/ranges, clone tokens, and summary inputs.
5. Context inputs (`active_file`, `mentioned_files`, `edited_files`, `changed_files`) are applied as query context.
6. `Dexterity` fetches symbols, validates cached summaries by mtime/signature, persists clone signatures, and renders deterministic file-level or symbol-level context text.
7. Mix tasks and MCP call the same public API modules.

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
