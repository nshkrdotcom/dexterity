defmodule Dexterity.SummaryWorker do
  @moduledoc """
  Caches short semantic summaries in the metadata store.
  """
  use GenServer

  alias Dexterity.Config
  alias Dexterity.Metadata
  alias Dexterity.Store
  alias Dexterity.StoreServer

  @default_retry_limit 2
  @default_retry_delay_ms 250

  @type summary_job :: %{
          file: String.t(),
          module_name: String.t(),
          mtime: integer(),
          signatures: term(),
          attempts: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    db_conn =
      case Keyword.fetch(opts, :db_conn) do
        {:ok, value} -> value
        :error -> StoreServer.conn()
      end

    state = %{
      db_conn: db_conn,
      llm_fn: Keyword.get(opts, :llm_fn, &default_llm_fn/1),
      enabled: Keyword.get(opts, :enabled, Config.fetch(:summary_enabled)),
      max_queue: Keyword.get(opts, :max_queue, 16),
      retry_limit: Keyword.get(opts, :retry_limit, @default_retry_limit),
      retry_delay_ms: Keyword.get(opts, :retry_delay_ms, @default_retry_delay_ms),
      queue: :queue.new(),
      working: false
    }

    GenServer.start_link(__MODULE__, state, name: name)
  end

  @spec summarize(
          GenServer.server(),
          String.t(),
          String.t(),
          integer(),
          term()
        ) :: :ok
  def summarize(server \\ __MODULE__, file, module_name, mtime, signatures) do
    GenServer.cast(server, {:summarize, file, module_name, mtime, signatures})
  end

  @spec status(GenServer.server()) :: map()
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:summarize, file, module_name, mtime, signatures}, state) do
    new_state =
      if state.enabled do
        enqueue_job(
          state,
          %{
            file: file,
            module_name: module_name,
            mtime: mtime,
            signatures: signatures,
            attempts: 0
          }
        )
      else
        state
      end

    {:noreply, maybe_start_processing(new_state)}
  end

  @impl true
  def handle_info({:summary_job_done, _job, result}, state) do
    state = %{state | working: false}

    new_state =
      case result do
        :ok ->
          state

        {:retry, job} ->
          Process.send_after(
            self(),
            {:queue_retry, %{job | attempts: job.attempts + 1}},
            state.retry_delay_ms
          )

          state
      end

    {:noreply, maybe_start_processing(new_state)}
  end

  @impl true
  def handle_info({:queue_retry, job}, state) do
    {:noreply, maybe_start_processing(enqueue_job(state, job))}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       enabled: state.enabled,
       working: state.working,
       queue_size: :queue.len(state.queue),
       max_queue: state.max_queue,
       retry_limit: state.retry_limit
     }, state}
  end

  defp maybe_start_processing(state) do
    if state.working do
      state
    else
      case :queue.out(state.queue) do
        {:empty, _} ->
          state

        {{:value, job}, queue} ->
          server = self()

          Task.start(fn ->
            send(server, {:summary_job_done, job, process_job(state, job)})
          end)

          %{state | working: true, queue: queue}
      end
    end
  end

  defp enqueue_job(state, %{} = job) do
    %{state | queue: bounded_enqueue(state.queue, state.max_queue, job)}
  end

  defp bounded_enqueue(queue, max_queue, _job) when max_queue <= 0, do: queue

  defp bounded_enqueue(queue, max_queue, job) do
    if :queue.len(queue) < max_queue do
      :queue.in(job, queue)
    else
      case :queue.out(queue) do
        {:empty, trimmed} ->
          trimmed

        {{:value, _dropped}, trimmed} ->
          :queue.in(job, trimmed)
      end
    end
  end

  defp process_job(state, %{} = job) do
    signature = Metadata.summary_signature(job.signatures)

    try do
      if is_nil(state.db_conn) do
        process_summary(state, job)
      else
        case Store.get_summary(state.db_conn, job.file, job.module_name) do
          {:ok, {_, cached_mtime, cached_signature}} ->
            if cached_mtime >= job.mtime and cached_signature == signature do
              :ok
            else
              process_summary(state, job)
            end

          _ ->
            process_summary(state, job)
        end
      end
    rescue
      _ ->
        process_summary(state, job)
    end
  end

  defp process_summary(state, job) do
    prompt = build_prompt(job)

    try do
      case state.llm_fn.(prompt) do
        {:ok, summary} when is_binary(summary) ->
          if is_nil(state.db_conn) do
            :ok
          else
            Store.upsert_summary(
              state.db_conn,
              job.file,
              job.module_name,
              summary,
              job.mtime,
              Metadata.summary_signature(job.signatures),
              System.os_time(:second)
            )
          end

        _ when job.attempts < state.retry_limit ->
          {:retry, job}

        _ ->
          :ok
      end
    rescue
      _ ->
        if job.attempts < state.retry_limit do
          {:retry, job}
        else
          :ok
        end
    end
  end

  defp build_prompt(job) do
    exported =
      case job.signatures do
        %{exports: exports} when is_list(exports) -> Enum.join(exports, ", ")
        _ -> inspect(job.signatures)
      end

    moduledoc =
      case job.signatures do
        %{moduledoc: nil} -> "none"
        %{moduledoc: value} -> value
        _ -> "none"
      end

    """
    Summarize this Elixir module in one short sentence (<=80 chars). Focus on
    responsibility, not implementation details.

    file: #{job.file}
    module: #{inspect(job.module_name)}
    moduledoc: #{moduledoc}
    exports: #{exported}
    """
  end

  defp default_llm_fn(_prompt) do
    {:error, :not_implemented}
  end
end
