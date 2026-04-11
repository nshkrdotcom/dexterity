defmodule Dexterity.GraphServer do
  @moduledoc """
  Manages computed file graphs and ranking state.
  """

  use GenServer

  alias Dexterity.Config
  alias Dexterity.Metadata
  alias Dexterity.PageRank
  alias Dexterity.Store
  alias Dexterity.StoreServer

  @type state :: %{
          repo_root: String.t(),
          backend: module(),
          store_conn: Dexterity.Store.db_conn(),
          graph: %{String.t() => %{String.t() => float()}},
          metadata: %{String.t() => map()},
          all_files: [String.t()],
          stale: boolean(),
          baseline: %{String.t() => float()}
        }

  # Client API

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_state(opts), name: name)
  end

  def get_repo_map(server \\ __MODULE__, context_files \\ [], opts \\ []) do
    GenServer.call(server, {:get_repo_map, context_files, opts}, 60_000)
  end

  def get_adjacency(server \\ __MODULE__) do
    GenServer.call(server, :get_adjacency, 60_000)
  end

  def get_metadata(server \\ __MODULE__) do
    GenServer.call(server, :get_metadata, 60_000)
  end

  def get_baseline_rank(server \\ __MODULE__) do
    GenServer.call(server, :get_baseline_rank, 60_000)
  end

  def mark_stale(server \\ __MODULE__) do
    GenServer.cast(server, :mark_stale)
  end

  @impl true
  def init(state) do
    send(self(), :build_graph)
    {:ok, state}
  end

  @impl true
  def handle_info(:build_graph, state) do
    {:noreply, rebuild_graph(state)}
  end

  @impl true
  def handle_cast(:mark_stale, state) do
    {:noreply, %{state | stale: true}}
  end

  @impl true
  def handle_call({:get_repo_map, context_files, opts}, _from, state) do
    state =
      if state.stale do
        rebuild_graph(state)
      else
        state
      end

    scores = compute_scores(state, context_files, opts)
    {:reply, {:ok, scores}, %{state | stale: false}}
  end

  @impl true
  def handle_call(:get_adjacency, _from, state) do
    {:reply, state.graph, state}
  end

  @impl true
  def handle_call(:get_metadata, _from, state) do
    state =
      if state.stale do
        rebuild_graph(state)
      else
        state
      end

    {:reply, state.metadata, %{state | stale: false}}
  end

  @impl true
  def handle_call(:get_baseline_rank, _from, state) do
    {:reply, state.baseline, state}
  end

  defp init_state(opts) do
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))

    store_conn =
      case Keyword.fetch(opts, :store_conn) do
        {:ok, value} -> value
        :error -> StoreServer.conn()
      end

    %{
      repo_root: repo_root,
      backend: backend,
      store_conn: store_conn,
      graph: %{},
      metadata: %{},
      all_files: [],
      stale: true,
      baseline: %{}
    }
  end

  defp compute_scores(state, context_files, opts) do
    context = normalize_context_files(context_files)
    all_files = Enum.uniq(context ++ state.all_files)
    config_context = Keyword.get(opts, :limit, nil)
    scores = PageRank.compute(state.graph, context, all_files)

    scores
    |> sort_scores()
    |> maybe_take(config_context)
  end

  defp sort_scores(scores) do
    Enum.sort_by(scores, fn {_file, score} -> score end, :desc)
  end

  defp maybe_take(scores, nil), do: scores
  defp maybe_take(scores, limit), do: Enum.take(scores, limit)

  defp normalize_context_files(context_files) do
    context_files
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp rebuild_graph(state) do
    edges = fetch_file_edges(state)
    cochange_edges = fetch_cochange_edges(state)
    file_nodes = fetch_file_nodes(state)
    candidate_files = collect_candidate_files(edges, file_nodes)
    metadata = Metadata.build(state.repo_root, candidate_files)

    merged = merge_edges(edges, cochange_edges, metadata.edges)
    all_files = collect_files(merged, file_nodes ++ Map.keys(metadata.files))

    sorted_all = Enum.sort(all_files)
    baseline = PageRank.compute(merged, [], sorted_all)

    cache_pagerank(state.store_conn, baseline)

    %{
      state
      | graph: merged,
        metadata: metadata.files,
        all_files: sorted_all,
        baseline: baseline,
        stale: false
    }
  end

  defp fetch_file_edges(state) do
    case state.backend.list_file_edges(state.repo_root) do
      {:ok, edges} -> edges
      _ -> []
    end
  end

  defp fetch_file_nodes(state) do
    case state.backend.list_file_nodes(state.repo_root) do
      {:ok, nodes} -> nodes
      _ -> []
    end
  end

  defp fetch_cochange_edges(%{store_conn: nil}), do: []

  defp fetch_cochange_edges(state) do
    if Config.cochange_enabled?() do
      case Store.list_cochanges(state.store_conn) do
        {:ok, edges} -> edges
        _ -> []
      end
    else
      []
    end
  end

  defp collect_files(graph, file_nodes) do
    nodes =
      graph
      |> Enum.reduce(MapSet.new(file_nodes), fn {source, targets}, acc ->
        target_nodes =
          targets
          |> Map.keys()

        Enum.reduce(
          target_nodes,
          MapSet.put(acc, source),
          fn target, node_set ->
            MapSet.put(node_set, target)
          end
        )
      end)

    MapSet.to_list(nodes)
  end

  defp collect_candidate_files(base_edges, file_nodes) do
    base_edges
    |> Enum.reduce(MapSet.new(file_nodes), fn {source, target, _weight}, acc ->
      acc
      |> MapSet.put(source)
      |> MapSet.put(target)
    end)
    |> MapSet.to_list()
  end

  defp merge_edges(base_edges, cochange_edges, metadata_edges) do
    base_edges
    |> Enum.reduce(%{}, fn {source, target, weight}, acc ->
      graph = Map.get(acc, source, %{})
      Map.put(acc, source, Map.update(graph, target, weight, &(&1 + weight)))
    end)
    |> merge_metadata_edges(metadata_edges)
    |> merge_cochanges(cochange_edges)
    |> normalize_empty_nodes()
  end

  defp merge_metadata_edges(graph, metadata_edges) do
    Enum.reduce(metadata_edges, graph, fn {source, target, weight}, acc ->
      edges = Map.get(acc, source, %{})
      updated_edges = Map.update(edges, target, weight, &(&1 + weight))
      Map.put(acc, source, updated_edges)
    end)
  end

  defp merge_cochanges(graph, cochanges) do
    cochanges
    |> Enum.reduce(graph, fn {file_a, file_b, _freq, weight}, acc ->
      source = Map.get(acc, file_a, %{})
      dest = Map.update(source, file_b, weight, &(&1 + weight))
      Map.put(acc, file_a, dest)
    end)
  end

  defp normalize_empty_nodes(graph) do
    graph
    |> Enum.reduce(%{}, fn {source, targets}, acc ->
      Map.put(acc, source, Map.reject(targets, fn {_file, weight} -> weight <= 0 end))
    end)
  end

  defp cache_pagerank(nil, _scores), do: :ok

  defp cache_pagerank(conn, scores) do
    now = System.os_time(:second)
    Store.upsert_pagerank_cache(conn, scores, now)
  end
end
