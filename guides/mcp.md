# MCP Server

Dexterity exposes a JSON-RPC/stdio MCP server through `mix dexterity.mcp.serve`.

## Protocol

- Transport: line-delimited JSON over stdin/stdout.
- Envelope:
  - `jsonrpc`: `"2.0"`
  - `id`: request identifier
  - `method`: either a root method (`initialize`, `tools/list`, `tools/call`, `shutdown`) or tool name
  - `params`: method arguments map

## Tools

- `query_references`
- `query_definition`
- `query_blast`
- `query_cochanges`
- `find_symbols`
- `match_files`
- `get_file_blast_radius`
- `get_file_graph_snapshot`
- `get_ranked_files`
- `get_ranked_symbols`
- `get_impact_context`
- `get_repo_map`
- `get_symbols`
- `get_symbol_graph_snapshot`
- `get_structural_snapshot`
- `get_export_analysis`
- `get_runtime_observations`
- `get_unused_exports`
- `get_test_only_exports`
- `get_module_deps`
- `status`

## Ranked file arguments

`get_ranked_files` accepts the same first-party filtering controls as the Elixir API and mix task:

- `include_prefixes` or `includePrefixes`
- `exclude_prefixes` or `excludePrefixes`
- `overscan_limit` or `overscanLimit`

Use these when Dexter has indexed `deps/` but the caller only wants first-party files such as `lib/`, `test/`, or `mix.exs`.

## Validation

- All parse failures return `error` with `code: -32700` (parse error) or `-32602` (invalid params).
- Missing method returns `-32601` (method not found).
- Method exceptions return `-32603` (internal error).

## Configuration

- Uses the same backend/repo runtime environment as API and mix tasks.
- When no matching running file-graph process exists for the requested backend/repo pair, file-graph snapshot and file-rank calls can build a temporary file graph for that request.
- When no matching running symbol-graph process exists for the requested backend/repo pair, symbol ranking calls can build a temporary symbol graph for that request.
- MCP is guarded by config and should be disabled in untrusted contexts.

## Operational posture

- MCP processing is designed to be explicit-failure-first:
  - Invalid request never mutates runtime state.
  - Unsupported features return immediate structured errors.
  - Server keeps running unless process-level fatal conditions occur.
