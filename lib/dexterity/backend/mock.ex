defmodule Dexterity.Backend.Mock do
  @moduledoc """
  Deterministic backend fixture for tests and offline scenarios.
  """

  @behaviour Dexterity.Backend

  defstruct [
    :file_edges,
    :file_nodes,
    :symbols_by_file,
    :definitions,
    :references,
    :index_status
  ]

  @type t :: %__MODULE__{
          file_edges: [{String.t(), String.t(), float()}],
          file_nodes: [String.t()],
          symbols_by_file: map(),
          definitions: [Dexterity.Backend.symbol()],
          references: [
            %{
              module: String.t(),
              function: String.t(),
              arity: integer(),
              file: String.t(),
              line: integer()
            }
          ],
          index_status: Dexterity.Backend.index_status()
        }

  def new(opts) do
    struct(
      __MODULE__,
      Keyword.merge(
        [
          file_edges: [],
          file_nodes: [],
          symbols_by_file: %{},
          definitions: [],
          references: [],
          index_status: :ready
        ],
        opts
      )
    )
  end

  defp state, do: Process.get(:dexterity_mock_backend, new([]))

  def start_link(state) do
    Process.put(:dexterity_mock_backend, state)
    {:ok, self()}
  end

  @impl Dexterity.Backend
  def list_file_edges(_repo_root), do: {:ok, state().file_edges}

  @impl Dexterity.Backend
  def list_file_nodes(_repo_root), do: {:ok, state().file_nodes}

  @impl Dexterity.Backend
  def list_exported_symbols(_repo_root, file),
    do: {:ok, Map.get(state().symbols_by_file, file, [])}

  @impl Dexterity.Backend
  def find_definition(_repo_root, module, function_name, arity) do
    matched =
      state().definitions
      |> Enum.filter(&(&1.module == module))
      |> maybe_filter_function(function_name)
      |> maybe_filter_arity(arity)

    if matched == [] do
      {:error, :not_found}
    else
      {:ok, matched}
    end
  end

  @impl Dexterity.Backend
  def find_references(_repo_root, module, function_name, arity) do
    refs = state().references

    filtered =
      refs
      |> Enum.filter(fn ref -> ref.module == module end)
      |> maybe_filter_reference_function(function_name)
      |> maybe_filter_reference_arity(arity)
      |> Enum.map(fn ref -> %{file: ref.file, line: ref.line} end)

    if filtered == [] do
      {:ok, []}
    else
      {:ok, filtered}
    end
  end

  @impl Dexterity.Backend
  def reindex_file(_file, _opts), do: :ok

  @impl Dexterity.Backend
  def cold_index(_repo_root, _opts), do: :ok

  @impl Dexterity.Backend
  def index_status(_repo_root), do: {:ok, state().index_status}

  @impl Dexterity.Backend
  def healthy?(_repo_root), do: {:ok, true}

  defp maybe_filter_function(symbols, nil), do: symbols

  defp maybe_filter_function(symbols, function_name),
    do: Enum.filter(symbols, &(&1.function == function_name))

  defp maybe_filter_arity(symbols, nil), do: symbols
  defp maybe_filter_arity(symbols, arity), do: Enum.filter(symbols, &(&1.arity == arity))

  defp maybe_filter_reference_function(refs, nil), do: refs

  defp maybe_filter_reference_function(refs, function_name),
    do: Enum.filter(refs, &(&1.function == function_name))

  defp maybe_filter_reference_arity(refs, nil), do: refs
  defp maybe_filter_reference_arity(refs, arity), do: Enum.filter(refs, &(&1.arity == arity))
end
