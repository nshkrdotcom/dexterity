# Kernel Surfaces

Dexterity should be treated as the structural kernel of a larger code-intelligence stack, not as the entire future platform.

## What Dexterity Owns

- Dexter-backed file graph ingestion
- symbol graph construction
- metadata enrichment
- blast radius and dependency analysis
- cochange ingestion
- callback-aware export analysis
- runtime observation persistence
- deterministic file, symbol, and combined structural snapshots

## What A Future Sibling Library Should Own

- semantic chunking and corpus policy
- embedding generation
- lexical/vector retrieval
- hybrid reranking over semantic plus structural signals
- model/provider integration

## Preferred Integration Contract

Use these APIs instead of reaching into internal servers:

- `Dexterity.get_file_graph_snapshot/1`
- `Dexterity.get_symbol_graph_snapshot/1`
- `Dexterity.get_structural_snapshot/1`
- `Dexterity.get_runtime_observations/1`
- `Dexterity.get_export_analysis/1`

The snapshots expose deterministic fingerprints so a sibling semantic indexer can decide when to rebuild its own derived state.
