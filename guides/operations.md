# Operations Guide

## Running and observability

- `Dexterity.status/0` should be the first check on runtime health:
  - backend status
  - database path
  - graph stale state
  - node count
- Use structured logs for graph stale rebuilds and worker failures.

## Failure modes

- Missing `.dexter.db`:
  - index should be treated as missing, not silent.
- Stale graph state:
  - rebuild on next request path and cache new ranking.
- Summary worker failures:
  - do not block ranking.
- Backend command failure:
  - explicit error return and no guessed result.

## Recommended cleanup

- Untracked or generated artifacts:
  - `test.db`
  - `test_db.exs`
  - `.dexterity/` during tests
- Remove these before release checkpoints and release handoff.

## Upgrade posture

- Keep implementation cleanly separated per module so backend and ranking policy changes can be landed incrementally.
