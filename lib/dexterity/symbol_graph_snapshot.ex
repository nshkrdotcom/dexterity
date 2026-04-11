defmodule Dexterity.SymbolGraphSnapshot do
  @moduledoc """
  Public, normalized export of Dexterity's symbol graph state.
  """

  @derive Jason.Encoder
  @enforce_keys [
    :repo_root,
    :backend,
    :nodes,
    :edges,
    :source_snippets,
    :generated_at,
    :fingerprint
  ]
  defstruct [:repo_root, :backend, :nodes, :edges, :source_snippets, :generated_at, :fingerprint]

  @type node_entry :: map()

  @type edge_entry :: %{
          source_id: String.t(),
          target_id: String.t(),
          weight: float()
        }

  @type t :: %__MODULE__{
          repo_root: String.t(),
          backend: String.t(),
          nodes: [node_entry()],
          edges: [edge_entry()],
          source_snippets: %{String.t() => String.t()},
          generated_at: integer(),
          fingerprint: String.t()
        }
end
