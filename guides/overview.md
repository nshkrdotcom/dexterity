# Dexterity Overview

Dexterity is an Elixir OTP library that builds ranked, context-aware codebase snapshots for LLM agents and tools.

## What it does

- Reads semantic graph data from `.dexter.db` (Dexter backend).
- Builds a file-to-file graph for PageRank ranking.
- Applies contextual boosts based on `active_file`, `mentioned_files`, and `edited_files`.
- Enriches rank signals with temporal coupling from `git log`.
- Produces token-bounded context blocks including symbols, summaries, dependents, and annotations.

## Core abstractions

- `Dexterity` public API for repo map, symbols, dependencies, and status.
- `Dexterity.Backend` behavior to abstract Dexter and future providers.
- `Dexterity.GraphServer` for graph/rank state and stale invalidation.
- `Dexterity.Store` for metadata tables (`cochanges`, `semantic_summaries`, `pagerank_cache`, `index_meta`).
- `Dexterity.CochangeWorker` for git-based temporal edges.
- `Dexterity.SummaryWorker` for cached LLM summary generation.
- `Dexterity.Query` and `Dexterity.Graph` read-facing modules.
