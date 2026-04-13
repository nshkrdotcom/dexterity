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

    if is_nil(name) do
      GenServer.start_link(__MODULE__, init_state(opts))
    else
      GenServer.start_link(__MODULE__, init_state(opts), name: name)
    end
  end

  def get_repo_map(server \\ __MODULE__, context_files \\ [], opts \\ []) do
    GenServer.call(server, {:get_repo_map, context_files, opts}, call_timeout(opts))
  end

  def get_adjacency(server \\ __MODULE__, opts \\ []) do
    GenServer.call(server, :get_adjacency, call_timeout(opts))
  end

  def get_metadata(server \\ __MODULE__, opts \\ []) do
    GenServer.call(server, :get_metadata, call_timeout(opts))
  end

  def get_baseline_rank(server \\ __MODULE__, opts \\ []) do
    GenServer.call(server, :get_baseline_rank, call_timeout(opts))
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
    state =
      if state.stale do
        rebuild_graph(state)
      else
        state
      end

    {:reply, state.baseline, %{state | stale: false}}
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
    limit = Keyword.get(opts, :limit, nil)
    conversation_terms = normalize_conversation_terms(Keyword.get(opts, :conversation_terms, []))
    scores = PageRank.compute(state.graph, context, all_files)
    boosted_scores = boost_scores(scores, state.metadata, conversation_terms)

    boosted_scores
    |> sort_scores()
    |> maybe_take(limit)
  end

  defp sort_scores(scores) do
    Enum.sort_by(scores, fn {file, score} -> {-score, file} end)
  end

  defp maybe_take(scores, nil), do: scores
  defp maybe_take(scores, limit), do: Enum.take(scores, limit)

  defp call_timeout(opts) do
    Keyword.get(
      opts,
      :timeout,
      Config.fetch(:server_call_timeout, Config.fetch(:server_call_timeout_ms, :infinity))
    )
  end

  defp normalize_context_files(context_files) do
    context_files
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp normalize_conversation_terms(nil), do: []

  defp normalize_conversation_terms(terms) when is_binary(terms) do
    normalize_conversation_terms([terms])
  end

  defp normalize_conversation_terms(terms) when is_list(terms) do
    terms
    |> Enum.flat_map(fn
      value when is_binary(value) ->
        Regex.scan(~r/[A-Za-z0-9_!?]+/, String.downcase(value))
        |> List.flatten()

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  defp normalize_conversation_terms(_terms), do: []

  defp boost_scores(scores, _metadata, []), do: scores

  defp boost_scores(scores, metadata, conversation_terms) do
    Map.new(scores, fn {file, score} ->
      {file, score + term_boost(file, Map.get(metadata, file, %{}), conversation_terms)}
    end)
  end

  defp term_boost(file, metadata, conversation_terms) do
    search_terms =
      metadata
      |> Map.get(:search_terms, [])
      |> MapSet.new()

    file_path = String.downcase(file)

    Enum.reduce(conversation_terms, 0.0, fn term, acc ->
      cond do
        String.contains?(file_path, term) ->
          acc + 0.6

        MapSet.member?(search_terms, term) ->
          acc + 0.45

        true ->
          acc
      end
    end)
  end

  defp rebuild_graph(state) do
    edges = fetch_file_edges(state)
    cochange_edges = fetch_cochange_edges(state)
    file_nodes = fetch_file_nodes(state)
    candidate_files = collect_candidate_files(edges, file_nodes)
    metadata = Metadata.build(state.repo_root, candidate_files)

    merged = merge_edges(edges, cochange_edges, metadata.edges)
    all_files = collect_files(merged, file_nodes ++ Map.keys(metadata.files))
    enriched_metadata = enrich_metadata(metadata.files, merged, all_files)

    sorted_all = Enum.sort(all_files)
    baseline = PageRank.compute(merged, [], sorted_all)

    cache_pagerank(state.store_conn, baseline)

    %{
      state
      | graph: merged,
        metadata: enriched_metadata,
        all_files: sorted_all,
        baseline: baseline,
        stale: false
    }
  end

  defp enrich_metadata(file_metadata, graph, all_files) do
    blast_radius = incoming_edge_counts(graph)

    Map.new(all_files, fn file ->
      metadata =
        file_metadata
        |> Map.get(file, %{})
        |> Map.put(:blast_radius, Map.get(blast_radius, file, 0))

      {file, metadata}
    end)
  end

  defp incoming_edge_counts(graph) do
    Enum.reduce(graph, %{}, fn {_source, targets}, acc ->
      Enum.reduce(Map.keys(targets), acc, fn target, counts ->
        Map.update(counts, target, 1, &(&1 + 1))
      end)
    end)
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
      acc
      |> put_weighted_edge(file_a, file_b, weight)
      |> put_weighted_edge(file_b, file_a, weight)
    end)
  end

  defp put_weighted_edge(graph, source, target, weight) do
    edges = Map.get(graph, source, %{})
    Map.put(graph, source, Map.update(edges, target, weight, &(&1 + weight)))
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
