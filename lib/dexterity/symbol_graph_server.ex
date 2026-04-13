defmodule Dexterity.SymbolGraphServer do
  @moduledoc """
  Manages computed symbol graphs and symbol-level ranking state.
  """

  use GenServer

  alias Dexterity.AnalysisSupport
  alias Dexterity.Config
  alias Dexterity.PageRank
  alias Dexterity.SymbolSource

  @type symbol_seed :: %{
          optional(:module) => String.t(),
          optional(:function) => String.t(),
          optional(:arity) => non_neg_integer(),
          optional(:file) => String.t()
        }

  @type ranking_context :: %{
          optional(:symbols) => [symbol_seed()],
          optional(:files) => [String.t()]
        }

  @type state :: %{
          repo_root: String.t(),
          backend: module(),
          graph: %{String.t() => %{String.t() => float()}},
          nodes: %{String.t() => map()},
          file_index: %{String.t() => [String.t()]},
          baseline: %{String.t() => float()},
          source_snippets: %{String.t() => String.t()},
          stale: boolean()
        }

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    if is_nil(name) do
      GenServer.start_link(__MODULE__, init_state(opts))
    else
      GenServer.start_link(__MODULE__, init_state(opts), name: name)
    end
  end

  @spec get_ranked_symbols(GenServer.server(), ranking_context(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def get_ranked_symbols(server \\ __MODULE__, context \\ %{}, opts \\ []) do
    GenServer.call(server, {:get_ranked_symbols, context, opts}, call_timeout(opts))
  end

  @spec get_adjacency(GenServer.server()) :: %{String.t() => %{String.t() => float()}}
  def get_adjacency(server \\ __MODULE__, opts \\ []) do
    GenServer.call(server, :get_adjacency, call_timeout(opts))
  end

  @spec get_nodes(GenServer.server()) :: %{String.t() => map()}
  def get_nodes(server \\ __MODULE__, opts \\ []) do
    GenServer.call(server, :get_nodes, call_timeout(opts))
  end

  @spec get_source_snippets(GenServer.server()) :: %{String.t() => String.t()}
  def get_source_snippets(server \\ __MODULE__, opts \\ []) do
    GenServer.call(server, :get_source_snippets, call_timeout(opts))
  end

  @spec get_baseline_rank(GenServer.server()) :: %{String.t() => float()}
  def get_baseline_rank(server \\ __MODULE__, opts \\ []) do
    GenServer.call(server, :get_baseline_rank, call_timeout(opts))
  end

  @spec mark_stale(GenServer.server()) :: :ok
  def mark_stale(server \\ __MODULE__) do
    GenServer.cast(server, :mark_stale)
  end

  @spec symbol_id(%{
          required(:module) => term(),
          required(:function) => term(),
          required(:arity) => term(),
          required(:file) => String.t()
        }) :: String.t()
  def symbol_id(symbol), do: SymbolSource.symbol_id(symbol)

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
  def handle_call({:get_ranked_symbols, context, opts}, _from, state) do
    state = maybe_rebuild(state)

    ranked =
      state
      |> compute_scores(context, opts)
      |> Enum.map(fn {id, rank} ->
        state.nodes
        |> Map.fetch!(id)
        |> Map.put(:rank, rank)
      end)

    {:reply, {:ok, ranked}, %{state | stale: false}}
  end

  @impl true
  def handle_call(:get_adjacency, _from, state) do
    state = maybe_rebuild(state)
    {:reply, state.graph, %{state | stale: false}}
  end

  @impl true
  def handle_call(:get_nodes, _from, state) do
    state = maybe_rebuild(state)
    {:reply, state.nodes, %{state | stale: false}}
  end

  @impl true
  def handle_call(:get_source_snippets, _from, state) do
    state = maybe_rebuild(state)
    {:reply, state.source_snippets, %{state | stale: false}}
  end

  @impl true
  def handle_call(:get_baseline_rank, _from, state) do
    state = maybe_rebuild(state)
    {:reply, state.baseline, %{state | stale: false}}
  end

  defp init_state(opts) do
    %{
      repo_root: Keyword.get(opts, :repo_root, Config.repo_root()),
      backend: Keyword.get(opts, :backend, Config.fetch(:backend)),
      graph: %{},
      nodes: %{},
      file_index: %{},
      baseline: %{},
      source_snippets: %{},
      stale: true
    }
  end

  defp maybe_rebuild(%{stale: true} = state), do: rebuild_graph(state)
  defp maybe_rebuild(state), do: state

  defp compute_scores(state, context, opts) do
    seed_ids = resolve_seed_ids(state, context)
    all_ids = Map.keys(state.nodes)
    limit = Keyword.get(opts, :limit)
    conversation_terms = normalize_conversation_terms(Keyword.get(opts, :conversation_terms, []))

    state.graph
    |> PageRank.compute(seed_ids, all_ids)
    |> boost_seed_scores(seed_ids)
    |> maybe_boost(conversation_terms, state.nodes)
    |> Enum.sort_by(fn {id, rank} -> {-rank, id} end)
    |> maybe_take(limit)
  end

  defp boost_seed_scores(scores, []), do: scores

  defp boost_seed_scores(scores, seed_ids) do
    Enum.reduce(seed_ids, scores, fn id, acc ->
      Map.update(acc, id, 1.0, &(&1 + 1.0))
    end)
  end

  defp maybe_boost(scores, [], _nodes), do: scores

  defp maybe_boost(scores, terms, nodes) do
    Map.new(scores, fn {id, score} ->
      {id, score + term_boost(Map.fetch!(nodes, id), terms)}
    end)
  end

  defp term_boost(symbol, terms) do
    search_blob =
      [symbol.module, symbol.function, symbol.file, Map.get(symbol, :signature, "")]
      |> Enum.join(" ")
      |> String.downcase()

    Enum.reduce(terms, 0.0, fn term, acc ->
      if String.contains?(search_blob, term) do
        acc + 0.3
      else
        acc
      end
    end)
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

  defp resolve_seed_ids(state, context) do
    file_ids =
      context
      |> Map.get(:files, [])
      |> Enum.flat_map(fn file -> Map.get(state.file_index, file, []) end)

    symbol_ids =
      context
      |> Map.get(:symbols, [])
      |> Enum.flat_map(&match_symbol_ids(state.nodes, &1))

    Enum.uniq(file_ids ++ symbol_ids)
  end

  defp match_symbol_ids(nodes, %{module: module, function: function, arity: arity} = seed)
       when is_binary(module) and is_binary(function) and is_integer(arity) do
    file = Map.get(seed, :file)

    nodes
    |> Map.values()
    |> Enum.filter(fn symbol ->
      symbol.module == module and symbol.function == function and symbol.arity == arity and
        (is_nil(file) or symbol.file == file)
    end)
    |> Enum.map(& &1.id)
  end

  defp match_symbol_ids(_nodes, _seed), do: []

  defp rebuild_graph(state) do
    nodes = fetch_symbol_nodes(state)
    node_map = Map.new(nodes, &{&1.id, &1})
    graph = build_graph(fetch_symbol_edges(state, node_map), Map.keys(node_map))
    baseline = PageRank.compute(graph, [], Map.keys(node_map))
    file_index = Enum.group_by(Map.keys(node_map), &node_map[&1].file)

    %{
      state
      | nodes: node_map,
        graph: graph,
        baseline: baseline,
        file_index: file_index,
        source_snippets: SymbolSource.snippets(state.repo_root, Map.values(node_map)),
        stale: false
    }
  end

  defp fetch_symbol_nodes(state) do
    nodes =
      with true <- function_exported?(state.backend, :list_symbol_nodes, 1),
           {:ok, listed_nodes} <- state.backend.list_symbol_nodes(state.repo_root) do
        SymbolSource.enrich(state.repo_root, listed_nodes)
      else
        _ -> fallback_symbol_nodes(state)
      end

    nodes
    |> Enum.filter(&AnalysisSupport.project_file?(state.repo_root, &1.file))
    |> Enum.sort_by(&{&1.file, &1.line, &1.module, &1.function, &1.arity})
  end

  defp fallback_symbol_nodes(state) do
    case AnalysisSupport.collect_symbols(state.backend, state.repo_root) do
      {:ok, symbols} -> SymbolSource.enrich(state.repo_root, symbols)
      _ -> []
    end
  end

  defp fetch_symbol_edges(state, node_map) do
    with true <- function_exported?(state.backend, :list_symbol_edges, 1),
         {:ok, edges} <- state.backend.list_symbol_edges(state.repo_root) do
      normalize_symbol_edges(edges, node_map)
    else
      _ -> fallback_symbol_edges(state, node_map)
    end
  end

  defp normalize_symbol_edges(edges, node_map) do
    edge_targets = symbol_targets_by_key(node_map)

    edges
    |> Enum.flat_map(fn edge ->
      source_ids = symbol_ids_for_ref(edge_targets, Map.get(edge, :source))
      target_ids = symbol_ids_for_ref(edge_targets, Map.get(edge, :target))
      weight = normalize_weight(Map.get(edge, :weight))

      for source_id <- source_ids, target_id <- target_ids do
        {source_id, target_id, weight}
      end
    end)
    |> collapse_edges()
  end

  defp fallback_symbol_edges(state, node_map) do
    targets_by_key = symbol_targets_by_key(node_map)
    file_ranges = file_ranges(node_map)

    node_map
    |> Map.values()
    |> Enum.flat_map(fn target ->
      case state.backend.find_references(
             state.repo_root,
             target.module,
             target.function,
             target.arity
           ) do
        {:ok, refs} ->
          target_ids = Map.get(targets_by_key, symbol_key(target), [])

          refs
          |> Enum.flat_map(fn ref ->
            source_ids = source_symbol_ids(file_ranges, ref)

            for source_id <- source_ids, target_id <- target_ids do
              {source_id, target_id, 1.0}
            end
          end)

        _ ->
          []
      end
    end)
    |> collapse_edges()
  end

  defp build_graph(edges, node_ids) do
    base = Map.new(node_ids, &{&1, %{}})

    Enum.reduce(edges, base, fn {source, target, weight}, acc ->
      outgoing = Map.get(acc, source, %{})
      Map.put(acc, source, Map.update(outgoing, target, weight, &(&1 + weight)))
    end)
  end

  defp collapse_edges(edges) do
    edges
    |> Enum.reduce(%{}, fn {source, target, weight}, acc ->
      Map.update(acc, {source, target}, weight, &(&1 + weight))
    end)
    |> Enum.map(fn {{source, target}, weight} -> {source, target, weight} end)
  end

  defp file_ranges(node_map) do
    node_map
    |> Map.values()
    |> Enum.group_by(& &1.file)
    |> Map.new(fn {file, nodes} ->
      {file, Enum.sort_by(nodes, &{&1.line, &1.end_line, &1.id})}
    end)
  end

  defp source_symbol_ids(file_ranges, %{file: file, line: line})
       when is_binary(file) and is_integer(line) do
    file_ranges
    |> Map.get(file, [])
    |> Enum.filter(fn node -> line >= node.line and line <= node.end_line end)
    |> Enum.map(& &1.id)
  end

  defp source_symbol_ids(_file_ranges, _ref), do: []

  defp symbol_targets_by_key(node_map) do
    Enum.group_by(Map.values(node_map), &symbol_key/1, & &1.id)
  end

  defp symbol_ids_for_ref(targets_by_key, %{module: module, function: function, arity: arity})
       when is_binary(module) and is_binary(function) and is_integer(arity) do
    Map.get(targets_by_key, {module, function, arity}, [])
  end

  defp symbol_ids_for_ref(_targets_by_key, %{id: id}) when is_binary(id), do: [id]

  defp symbol_ids_for_ref(_targets_by_key, _ref), do: []

  defp symbol_key(%{module: module, function: function, arity: arity}),
    do: {module, function, arity}

  defp normalize_weight(weight) when is_number(weight) and weight > 0, do: weight * 1.0
  defp normalize_weight(_weight), do: 1.0
end
