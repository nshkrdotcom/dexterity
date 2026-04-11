defmodule Dexterity.SummaryWorker do
  @moduledoc """
  Caches short semantic summaries in the metadata store.
  """
  use GenServer

  alias Dexterity.Config
  alias Dexterity.Store
  alias Dexterity.StoreServer

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    db_conn = Keyword.get(opts, :db_conn, StoreServer.conn())

    state = %{
      db_conn: db_conn,
      llm_fn: Keyword.get(opts, :llm_fn, &default_llm_fn/1),
      enabled: Keyword.get(opts, :enabled, Config.fetch(:summary_enabled)),
      max_queue: Keyword.get(opts, :max_queue, 16)
    }

    GenServer.start_link(__MODULE__, state, name: name)
  end

  def summarize(server \\ __MODULE__, file, module_name, mtime, signatures) do
    GenServer.cast(server, {:summarize, file, module_name, mtime, signatures})
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:summarize, file, module_name, mtime, signatures}, state) do
    if state.enabled do
      case Store.get_summary(state.db_conn, file, module_name) do
        {:ok, {_, cached_mtime}} when cached_mtime >= mtime ->
          :ok

        _ ->
          process_summary(state, file, module_name, mtime, signatures)
      end
    end

    {:noreply, state}
  end

  defp process_summary(state, file, module_name, mtime, signatures) do
    prompt =
      """
      Summarize this Elixir module in one short sentence (<=80 chars). Focus on
      responsibility, not implementation details.

      #{signatures}
      """

    case state.llm_fn.(prompt) do
      {:ok, summary} ->
        Store.upsert_summary(state.db_conn, file, module_name, summary, mtime, System.os_time(:second))

      _ ->
        :ok
    end
  end

  defp default_llm_fn(_prompt) do
    {:error, :not_implemented}
  end
end
