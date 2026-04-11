defmodule Dexterity.Indexer do
  @moduledoc """
  Ensures dexter index lifecycle at startup and on demand.
  """

  use GenServer

  alias Dexterity.Config

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_state(opts), name: name)
  end

  def refresh(server \\ __MODULE__) do
    GenServer.cast(server, :refresh)
  end

  @impl true
  def init(state) do
    ensure_index(state)
    schedule_check(state.interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    ensure_index(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:ensure_index, state) do
    ensure_index(state)
    schedule_check(state.interval_ms)
    {:noreply, state}
  end

  defp init_state(opts) do
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))
    interval_ms = Keyword.get(opts, :interval_ms, 60_000)

    %{
      repo_root: repo_root,
      backend: backend,
      interval_ms: interval_ms
    }
  end

  defp ensure_index(state) do
    with {:ok, :missing} <- state.backend.index_status(state.repo_root),
         :ok <- state.backend.cold_index(state.repo_root) do
      :ok
    else
      {:ok, :ready} ->
        :ok

      {:ok, :stale} ->
        state.backend.cold_index(state.repo_root)

      {:error, _reason} ->
        :ok
    end
  end

  defp schedule_check(interval_ms) do
    Process.send_after(self(), :ensure_index, interval_ms)
  end
end
