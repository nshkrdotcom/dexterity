# Buildout Playbook

## Required development model

- Read and keep this flow:
  - `codex-spark/README.md`
  - `codex-spark/implementation_reading_and_context.md`
  - `codex-spark/implementation_plan_tdd_rgr.md`
  - `codex-spark/full_execution_checklist.md`
  - `codex-spark/recontextualization_instructions.md`
- Always add one failing test first.
- Green implementation, then refactor.
- Run all quality gates before every phase handoff.

## Quality gates

- `mix test`
- `mix compile`
- `mix credo`
- `mix dialyzer`

## Build phases

- Stabilize API/query behavior and error contracts.
- Complete mix task and MCP transport behaviors.
- Add summary/metadata hardening and queue policy.
- Improve graph enrichment + clone/use protocol rendering.
- Final acceptance and release hygiene.

Current checkpoint:
- Graph enrichment, clone rendering, and summary cache invalidation are complete.
- Remaining work is release hygiene and any follow-on operational tooling, not core repo-map behavior.

## Compaction rule

- Re-open checklist immediately after any context switch.
- Update `as_built_assessment.md`, `implementation_plan_tdd_rgr.md`, and `full_execution_checklist.md` before next behavior change.
