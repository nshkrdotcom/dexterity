# Architecture Guide

## Data flow

1. `Indexer` ensures Dexter index state at startup and on schedule.
2. `GraphServer` fetches:
   - base file edges from `Backend` (`dexter.definitions`, `dexter.references`)
   - co-change edges from `Store`
3. Edges merge and normalize into adjacency map.
4. PageRank computes baseline and contextual scores.
5. `get_repo_map` fetches ranked symbols and optional summaries, then renders Markdown output.

## OTP structure

- `Dexterity.Application` supervises core servers:
  - `StoreServer`
  - `IndexSupervisor` (`Indexer`, `FileWatcher`)
  - `GraphServer`
  - `CochangeWorker`
  - `SummaryWorker`

## Determinism controls

- Graph rebuild is lazy and controlled via stale marker.
- Ranking is pure and deterministic for fixed graph + context.
- Tokenized output is assembled in deterministic order.

## Out-of-scope in current baseline

- MCP task wiring and full mix task surface are planned, not fully delivered yet.
