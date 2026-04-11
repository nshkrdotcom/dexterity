# Testing and Quality

## Mandatory quality sequence

- `mix test`
- `mix compile`
- `mix credo`
- `mix dialyzer`

All three are required before any phase handoff.

## Test strategy

- Unit-first for each facade (`Dexterity`, `Backend`, `Graph`, `Store`, workers).
- Property-style checks where deterministic ranking or dedupe is involved.
- Negative-path tests for all backend and storage failures.
- Integration checks using temporary scratch DBs and temporary repos.

## Current baseline

- `mix test`: 26 passing at last snapshot.
- `mix compile`: passing.
- `mix credo`: passing.
- `mix dialyzer`: not yet clean (14 contract issues).

## Acceptance gate targets

- 100% required checks are green.
- No temporary artifacts tracked in git for release-ready handoff.
- Checklists updated and as-built assessment refreshed at each phase boundary.
