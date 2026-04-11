defmodule Dexterity.FileGraphSnapshot do
  @moduledoc """
  Public, normalized export of Dexterity's file graph state.
  """

  @derive Jason.Encoder
  @enforce_keys [:repo_root, :backend, :files, :edges, :generated_at, :fingerprint]
  defstruct [:repo_root, :backend, :files, :edges, :generated_at, :fingerprint]

  @type file_entry :: %{
          file: String.t(),
          rank: float(),
          metadata: map()
        }

  @type edge_entry :: %{
          source: String.t(),
          target: String.t(),
          weight: float()
        }

  @type t :: %__MODULE__{
          repo_root: String.t(),
          backend: String.t(),
          files: [file_entry()],
          edges: [edge_entry()],
          generated_at: integer(),
          fingerprint: String.t()
        }
end
