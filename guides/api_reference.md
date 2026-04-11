# API Reference

This guide summarizes primary runtime behavior.

## Core API (`Dexterity`)

- `get_repo_map(context_opts()) :: {:ok, String.t()} | {:error, term()}`
  - Returns rendered, ranked context.
  - Hard-bounds token budget.
- `get_ranked_files(context_opts()) :: {:ok, [{file, score}]}`.
- `get_symbols(file, opts \\\\ []) :: {:ok, [map()]} | {:error, :not_indexed} | {:error, term()}`
- `get_module_deps(file, opts \\\\ []) :: {:ok, %{dependencies: [file], dependents: [file]}} | {:error, term()}`
- `notify_file_changed(file, opts \\\\ []) :: :ok | {:error, term()}`
- `status() :: {:ok, map()} | {:error, term()}`

## Query API (`Dexterity.Query`)

- `find_references(module, function \\\\ nil, arity \\\\ nil, opts \\\\ [])`
- `find_definition(module, function \\\\ nil, arity \\\\ nil, opts \\\\ [])`
- `blast_radius(file, opts \\\\ [])`
- `cochanges(file, limit \\\\ 10, opts \\\\ [])` (planned; ensure added if absent)

## Graph API (`Dexterity.Graph`)

- `get_adjacency(opts \\\\ [])`
- `pagerank(context_files, opts \\\\ [])`
- `baseline(opts \\\\ [])`

## Stability notes

- Error semantics should be explicit; avoid returning fallback placeholders for failed backends.
- API changes must remain spec-aligned and have matching behavior tests.
