# Architecture

## Runtime architecture

- `Dexterity.Application` starts OTP supervision:
  - `StoreServer` for metadata DB lifecycle.
  - `IndexSupervisor` with `Indexer` + `FileWatcher`.
  - `GraphServer` for graph/rank state.
  - `CochangeWorker` for temporal coupling.
  - `SummaryWorker` for optional summary cache updates.

## Data and control path

1. Backend reads `.dexter.db` for semantic edges and symbol exports.
2. `GraphServer` builds a ranked adjacency map:
   - base edges from backend
   - temporal edges from `Store`
3. Context inputs (`active_file`, `mentioned_files`, `edited_files`) are applied as query context.
4. `Dexterity` fetches symbols and summaries and renders deterministic map text.
5. Mix tasks and MCP call the same public API modules.

## Build boundaries

- Backends are injected via `Dexterity.Backend` callbacks.
- Graph rebuild is lazy and triggered when stale state is detected.
- Metadata persistence happens in local SQLite metadata store (`Store`).
- MCP runs as an explicit transport layer over the same public functions.

## Stability points

- Backend missing DB returns explicit status values.
- Missing graph state does not produce guessed output.
- Ranking and renderer operate in deterministic order.
- Summary worker failures do not block ranking reads.
