defmodule Dexterity.StructuralExports do
  @moduledoc false

  alias Dexterity.AnalysisSupport
  alias Dexterity.FileGraphSnapshot
  alias Dexterity.GraphServer
  alias Dexterity.SnapshotSupport
  alias Dexterity.StructuralSnapshot
  alias Dexterity.SymbolGraphServer
  alias Dexterity.SymbolGraphSnapshot

  @spec build_file_graph_snapshot(GenServer.server(), keyword()) ::
          {:ok, FileGraphSnapshot.t()}
  def build_file_graph_snapshot(graph_server, opts) do
    repo_root = opts |> Keyword.fetch!(:repo_root) |> Path.expand()
    backend = opts |> Keyword.fetch!(:backend) |> inspect()
    metadata = GraphServer.get_metadata(graph_server)
    baseline = GraphServer.get_baseline_rank(graph_server)
    adjacency = GraphServer.get_adjacency(graph_server)
    generated_at = System.os_time(:second)

    project_files =
      metadata
      |> Map.keys()
      |> Kernel.++(Map.keys(adjacency))
      |> Kernel.++(Map.keys(baseline))
      |> Kernel.++(Enum.flat_map(adjacency, fn {_source, targets} -> Map.keys(targets) end))
      |> Enum.filter(&AnalysisSupport.project_file?(repo_root, &1))
      |> Enum.uniq()
      |> Enum.sort()

    files =
      Enum.map(project_files, fn file ->
        %{
          file: file,
          rank: Map.get(baseline, file, 0.0),
          metadata: Map.get(metadata, file, %{})
        }
      end)

    edges =
      adjacency
      |> Enum.flat_map(fn {source, targets} ->
        if source in project_files do
          targets
          |> Enum.filter(fn {target, _weight} -> target in project_files end)
          |> Enum.map(fn {target, weight} ->
            %{source: source, target: target, weight: weight}
          end)
        else
          []
        end
      end)
      |> Enum.sort_by(&{&1.source, &1.target, &1.weight})

    payload = %{repo_root: repo_root, backend: backend, files: files, edges: edges}

    {:ok,
     %FileGraphSnapshot{
       repo_root: repo_root,
       backend: backend,
       files: files,
       edges: edges,
       generated_at: generated_at,
       fingerprint: SnapshotSupport.fingerprint(payload)
     }}
  end

  @spec build_symbol_graph_snapshot(GenServer.server(), keyword()) ::
          {:ok, SymbolGraphSnapshot.t()}
  def build_symbol_graph_snapshot(symbol_graph_server, opts) do
    repo_root = opts |> Keyword.fetch!(:repo_root) |> Path.expand()
    backend = opts |> Keyword.fetch!(:backend) |> inspect()
    nodes = SymbolGraphServer.get_nodes(symbol_graph_server)
    baseline = SymbolGraphServer.get_baseline_rank(symbol_graph_server)
    snippets = SymbolGraphServer.get_source_snippets(symbol_graph_server)
    adjacency = SymbolGraphServer.get_adjacency(symbol_graph_server)
    generated_at = System.os_time(:second)

    normalized_nodes =
      nodes
      |> Map.values()
      |> Enum.filter(&AnalysisSupport.project_file?(repo_root, &1.file))
      |> Enum.map(fn node ->
        node
        |> Map.put(:rank, Map.get(baseline, node.id, 0.0))
      end)
      |> Enum.sort_by(&{&1.file, &1.line, &1.module, &1.function, &1.arity})

    node_ids = MapSet.new(Enum.map(normalized_nodes, & &1.id))

    normalized_edges =
      adjacency
      |> Enum.flat_map(fn {source_id, targets} ->
        if MapSet.member?(node_ids, source_id) do
          targets
          |> Enum.filter(fn {target_id, _weight} -> MapSet.member?(node_ids, target_id) end)
          |> Enum.map(fn {target_id, weight} ->
            %{source_id: source_id, target_id: target_id, weight: weight}
          end)
        else
          []
        end
      end)
      |> Enum.sort_by(&{&1.source_id, &1.target_id, &1.weight})

    normalized_snippets =
      snippets
      |> Enum.filter(fn {id, _snippet} -> MapSet.member?(node_ids, id) end)
      |> Enum.sort_by(fn {id, _snippet} -> id end)
      |> Map.new()

    payload = %{
      repo_root: repo_root,
      backend: backend,
      nodes: normalized_nodes,
      edges: normalized_edges,
      source_snippets: normalized_snippets
    }

    {:ok,
     %SymbolGraphSnapshot{
       repo_root: repo_root,
       backend: backend,
       nodes: normalized_nodes,
       edges: normalized_edges,
       source_snippets: normalized_snippets,
       generated_at: generated_at,
       fingerprint: SnapshotSupport.fingerprint(payload)
     }}
  end

  @spec build_structural_snapshot(
          FileGraphSnapshot.t(),
          SymbolGraphSnapshot.t(),
          keyword()
        ) :: StructuralSnapshot.t()
  def build_structural_snapshot(file_graph, symbol_graph, opts) do
    repo_root = Keyword.fetch!(opts, :repo_root) |> Path.expand()
    backend = Keyword.fetch!(opts, :backend) |> inspect()
    runtime_observations = Keyword.get(opts, :runtime_observations)
    export_analysis = Keyword.get(opts, :export_analysis)
    generated_at = System.os_time(:second)

    payload = %{
      repo_root: repo_root,
      backend: backend,
      file_graph: file_graph,
      symbol_graph: symbol_graph,
      runtime_observations: runtime_observations,
      export_analysis: export_analysis
    }

    %StructuralSnapshot{
      repo_root: repo_root,
      backend: backend,
      file_graph: file_graph,
      symbol_graph: symbol_graph,
      runtime_observations: runtime_observations,
      export_analysis: export_analysis,
      generated_at: generated_at,
      fingerprint: SnapshotSupport.fingerprint(payload)
    }
  end
end
