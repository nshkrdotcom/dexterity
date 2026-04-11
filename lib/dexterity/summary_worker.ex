defmodule Dexterity.SummaryWorker do
  @moduledoc """
  Background worker to fetch and cache LLM summaries for top-ranked modules.
  """
  use GenServer

  alias Exqlite.Basic

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    db_conn = Keyword.fetch!(opts, :db_conn)
    llm_fn = Keyword.get(opts, :llm_fn, &default_llm_fn/1)

    GenServer.start_link(
      __MODULE__,
      %{
        db_conn: db_conn,
        llm_fn: llm_fn
      },
      name: name
    )
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
    # In a real app, this might check a local cache first, but we assume
    # the caller checked the DB and realized it was missing or stale.

    prompt = """
    System: You are a code documentation assistant.
    User: Summarize this Elixir module in exactly one sentence under 80 characters.
          Focus on what it does, not how.

    #{signatures}
    """

    case state.llm_fn.(prompt) do
      {:ok, summary} ->
        now = System.os_time(:second)

        sql = """
        INSERT INTO semantic_summaries (file, module, summary, file_mtime, created_at)
        VALUES (?1, ?2, ?3, ?4, ?5)
        ON CONFLICT(file, module) DO UPDATE SET
          summary = excluded.summary,
          file_mtime = excluded.file_mtime,
          created_at = excluded.created_at
        """

        Basic.exec(state.db_conn, sql, [file, module_name, summary, mtime, now])

      _ ->
        :ignore
    end

    {:noreply, state}
  end

  defp default_llm_fn(_prompt) do
    {:error, :not_implemented}
  end
end
