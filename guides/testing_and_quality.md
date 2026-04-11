# Testing and Quality

## Mandatory quality sequence

- `mix test`
- `mix compile`
- `mix credo`
- `mix dialyzer`

All four are required before phase transition.

## Test strategy

- Unit-first for each facade (`Dexterity`, `Backend`, `Graph`, `Store`, workers).
- Negative-path tests for every API contract and CLI arg parse branch.
- Integration checks using temporary repos, temp DBs, and temporary worker state.
- Deterministic assertions for ranking and traversal order.
- Stability checks for queue/retry and malformed MCP payload handling.

## Current baseline

- `mix test`: 38 passing
- `mix compile`: passing
- `mix credo`: passing
- `mix dialyzer`: passing

## Acceptance gate targets

- 100% required checks must pass before merge.
- No ephemeral DB artifacts in release handoff.
- Guide and packet checklists remain updated after every compaction.

## Required quality tags for this branch

- New behavior must include at least one failing test first.
- Any non-trivial behavior change requires one regression test after refactor.
- No API behavior changes without protocol-level docs updated in `guides/`.
