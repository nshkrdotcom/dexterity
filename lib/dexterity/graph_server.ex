defmodule Dexterity.GraphServer do
  @moduledoc """
  GenServer that maintains the file dependency graph and computes PageRank.
  """
  use GenServer

  alias Dexterity.Backend.Dexter

  @type state :: %{
          repo_root: String.t(),
          graph: map(),
          all_files: [String.t()],
          baseline_ranks: map(),
          stale: boolean()
        }

  # --- Client API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    repo_root = Keyword.fetch!(opts, :repo_root)
    GenServer.start_link(__MODULE__, %{repo_root: repo_root}, name: name)
  end

  def get_repo_map(server \\ __MODULE__, context_files \\ []) do
    GenServer.call(server, {:get_repo_map, context_files}, 60_000)
  end

  def mark_stale(server \\ __MODULE__) do
    GenServer.cast(server, :mark_stale)
  end

  # --- Server Callbacks ---

  @impl true
  def init(%{repo_root: repo_root}) do
    # Defer initial load to not block startup
    send(self(), :build_graph)

    {:ok,
     %{
       repo_root: repo_root,
       graph: %{},
       all_files: [],
       baseline_ranks: %{},
       stale: true
     }}
  end

  @impl true
  def handle_info(:build_graph, state) do
    new_state = do_build_graph(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:mark_stale, state) do
    {:noreply, %{state | stale: true}}
  end

  @impl true
  def handle_call({:get_repo_map, context_files}, _from, state) do
    state =
      if state.stale do
        do_build_graph(state)
      else
        state
      end

    ranks =
      if context_files == [] do
        state.baseline_ranks
      else
        Dexterity.PageRank.compute(state.graph, context_files, state.all_files)
      end

    {:reply, {:ok, ranks}, state}
  end

  # --- Internal Functions ---

  defp do_build_graph(state) do
    edges = Dexter.list_file_edges(state.repo_root)

    # Build adjacency list: %{source => %{target => weight}}
    graph =
      Enum.reduce(edges, %{}, fn {source, target, weight}, acc ->
        acc
        |> Map.put_new(source, %{})
        |> put_in([source, target], weight)
      end)

    # Collect all unique files
    all_files_set =
      Enum.reduce(edges, MapSet.new(), fn {s, t, _}, acc ->
        acc |> MapSet.put(s) |> MapSet.put(t)
      end)

    all_files = MapSet.to_list(all_files_set)

    # Compute baseline
    baseline = Dexterity.PageRank.compute(graph, [], all_files)

    %{state | graph: graph, all_files: all_files, baseline_ranks: baseline, stale: false}
  end
end
