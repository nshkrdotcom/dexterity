# Buildout Playbook

## TDD + RGR Rules

1. Add failing test first.
2. Make minimal change to pass.
3. Refactor while preserving green.
4. Expand tests before expanding behavior.

## Phase-by-phase execution

1. API contract completion
2. Backend hardening
3. Store and lifecycle
4. Graph intelligence
5. Render + summaries
6. Mix + MCP
7. Performance and hardening

## Re-entry protocol

- Re-open `codex-spark/` packet before resuming implementation.
- Confirm checklist states are true before each phase.
- Never continue without running at least local `mix test`.

## Compaction handling

- After each major context switch, re-read:
  - `as_built_assessment.md`
  - `full_execution_checklist.md`
  - `implementation_plan_tdd_rgr.md`
- Keep decisions logged; never re-derive unresolved design choices without tests.
