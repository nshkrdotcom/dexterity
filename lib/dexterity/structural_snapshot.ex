defmodule Dexterity.StructuralSnapshot do
  @moduledoc """
  Public, combined structural snapshot for downstream Dexterity consumers.
  """

  @derive Jason.Encoder
  @enforce_keys [:repo_root, :backend, :file_graph, :symbol_graph, :generated_at, :fingerprint]
  defstruct [
    :repo_root,
    :backend,
    :file_graph,
    :symbol_graph,
    :runtime_observations,
    :export_analysis,
    :generated_at,
    :fingerprint
  ]

  @type t :: %__MODULE__{
          repo_root: String.t(),
          backend: String.t(),
          file_graph: Dexterity.FileGraphSnapshot.t(),
          symbol_graph: Dexterity.SymbolGraphSnapshot.t(),
          runtime_observations: [map()] | nil,
          export_analysis: [map()] | nil,
          generated_at: integer(),
          fingerprint: String.t()
        }
end
