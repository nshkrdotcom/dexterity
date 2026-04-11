defmodule Dexterity.FileWatcher do
  @moduledoc """
  Watches files and triggers file-local reindex + graph invalidation.
  """

  use GenServer

  alias Dexterity.Backend.Dexter
  alias Dexterity.Config
  alias Dexterity.GraphServer

  @extensions [".ex", ".exs"]

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_state(opts), name: name)
  end

  @impl true
  def init(state) do
    maybe_init_watcher(state)
    {:ok, state}
  end

  defp init_state(opts) do
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))
    debounce_ms = Keyword.get(opts, :debounce_ms, Config.fetch(:watch_debounce_ms))
    graph_server = Keyword.get(opts, :graph_server, GraphServer)

    %{
      repo_root: repo_root,
      backend: backend,
      debounce_ms: debounce_ms,
      graph_server: graph_server,
      pending: MapSet.new()
    }
  end

  defp maybe_init_watcher(state) do
    case state.backend do
      Dexter ->
        if Code.ensure_loaded?(:file_system) and function_exported?(:file_system, :start_link, 1) do
          {:ok, watcher} =
            :erlang.apply(:file_system, :start_link,
              dirs: [state.repo_root],
              name: :"dexterity_file_system_#{System.unique_integer([:positive])}"
            )

          :erlang.apply(:file_system, :subscribe, [watcher])
          Process.monitor(watcher)
          :ok
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  @impl true
  def handle_info({:file_event, _watcher, {path, events}}, state) do
    ext = Path.extname(path)

    if ext in @extensions && changed_event?(events) do
      send(self(), {:changed, path})
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:noop, state), do: {:noreply, state}

  @impl true
  def handle_info({:changed, path}, state) do
    was_empty = state.pending == MapSet.new()

    new_state =
      state
      |> Map.update!(:pending, &MapSet.put(&1, path))
      |> schedule_reindex(was_empty)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:flush, state) do
    files = MapSet.to_list(state.pending)

    Enum.each(files, fn file ->
      state.backend.reindex_file(file, repo_root: state.repo_root)
    end)

    if files != [] do
      GraphServer.mark_stale(state.graph_server)
    end

    {:noreply, %{state | pending: MapSet.new()}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  defp schedule_reindex(state, true) do
    if map_size(state.pending) >= 1 do
      Process.send_after(self(), :flush, state.debounce_ms)
    end

    state
  end

  defp schedule_reindex(state, false), do: state

  defp changed_event?(events) when is_list(events) do
    Enum.any?(events, &match?({:modified, _}, &1))
  end

  defp changed_event?(_), do: false
end
