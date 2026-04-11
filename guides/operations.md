# Operations Guide

## Operational checks

Run this sequence before major handoffs:

1. `mix test`
2. `mix compile`
3. `mix credo`
4. `mix dialyzer`
5. `mix dexterity.status`
6. `mix dexterity.map --repo-root . --limit 5`

## Runtime behavior

- `Dexterity.status/0` is the root health signal:
  - backend readiness/health
  - index path
  - stale graph state
  - number of nodes in the graph map
- Graph rebuild is lazy: stale graphs refresh on first call that needs ranking.
- File changes are queued by `FileWatcher` and may debounce depending on timer config.
- Co-change updates happen on schedule and are non-blocking to map rendering.

## Failure modes and recovery

- Missing `.dexter.db`:
  - status reports index as `:missing`
  - run `mix dexterity.index --repo-root .` and rerun status
- Stale graph:
  - first ranking call after staleness rebuilds; no partial ranking result is returned
- Backend command failure:
  - explicit error tuple is returned; no fallback synthesis
- MCP malformed payload:
  - server returns JSON-RPC error object; process remains alive
- Summary queue saturation:
  - bounded queue policy drops oldest request when full

## Observability

- Log and inspect:
  - graph stale/refresh transitions
  - indexer bootstrap errors
  - co-change worker errors and retry paths
  - MCP validation failures

## Repository hygiene

- Remove ephemeral artifacts before release checkpoints:
  - `test.db`
  - `test_db.exs`
  - `.dexterity/` (test workspace only)
