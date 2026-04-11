defmodule Dexterity do
  @moduledoc """
  Core public API for Dexterity.
  """

  alias Dexterity.Config
  alias Dexterity.GraphServer
  alias Dexterity.Intelligence
  alias Dexterity.Metadata
  alias Dexterity.Render
  alias Dexterity.Store
  alias Dexterity.StoreServer
  alias Dexterity.SummaryWorker

  @type context_opts :: [
          active_file: String.t(),
          mentioned_files: [String.t()],
          edited_files: [String.t()],
          conversation_terms: [String.t()],
          conversation_tokens: non_neg_integer(),
          token_budget: pos_integer() | :auto,
          include_clones: boolean(),
          min_rank: float(),
          limit: pos_integer(),
          backend: module(),
          repo_root: String.t(),
          graph_server: GenServer.server(),
          summary_server: GenServer.server(),
          store_conn: Dexterity.Store.db_conn() | nil,
          summary_enabled: boolean()
        ]

  @type status_snapshot :: %{
          backend: String.t(),
          dexter_db: String.t(),
          index_status: atom(),
          backend_healthy: boolean(),
          graph_stale: boolean(),
          files: non_neg_integer()
        }

  @type ranked_symbol :: %{
          module: String.t(),
          function: String.t(),
          arity: non_neg_integer(),
          file: String.t(),
          line: non_neg_integer(),
          rank: float()
        }

  @type unused_export :: %{
          module: String.t(),
          function: String.t(),
          arity: non_neg_integer(),
          file: String.t(),
          line: non_neg_integer(),
          used_internally: boolean()
        }

  @doc """
  Returns ranked and rendered repository context.
  """
  @spec get_repo_map(context_opts()) :: {:ok, String.t()} | {:error, term()}
  def get_repo_map(opts \\ []) do
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    graph_server = Keyword.get(opts, :graph_server, GraphServer)
    budget = Keyword.get(opts, :token_budget, :auto)
    {min_budget, default_budget, max_budget} = Config.token_budget_range()

    budget =
      clamp_budget(
        budget,
        min_budget,
        max_budget,
        default_budget,
        Keyword.get(opts, :conversation_tokens)
      )

    limit = Keyword.get(opts, :limit, 25)
    include_clones = Keyword.get(opts, :include_clones, Config.fetch(:include_clones))

    context_files = context_files(opts)
    conversation_terms = Keyword.get(opts, :conversation_terms, [])

    with {:ok, ranked} <-
           GraphServer.get_repo_map(
             graph_server,
             context_files,
             limit: limit,
             conversation_terms: conversation_terms
           ),
         {:ok, ranked_list} <- normalize_ranked(ranked, Keyword.get(opts, :min_rank, 0.0)),
         {:ok, metadata} <- fetch_metadata(graph_server),
         {:ok, symbols} <- fetch_symbols(backend, repo_root, ranked_list),
         {:ok, summaries} <- fetch_summaries(ranked_list, metadata, symbols, repo_root, opts),
         {:ok, clones} <- detect_clones(ranked_list, metadata, include_clones, opts) do
      {:ok, Render.render_files(ranked_list, symbols, summaries, clones, metadata, budget)}
    end
  end

  @doc """
  Returns ranked files ordered by relevance.
  """
  @spec get_ranked_files(context_opts()) :: {:ok, [{String.t(), float()}]} | {:error, term()}
  def get_ranked_files(opts \\ []) do
    graph_server = Keyword.get(opts, :graph_server, GraphServer)
    limit = Keyword.get(opts, :limit, 200)

    context_files = context_files(opts)
    conversation_terms = Keyword.get(opts, :conversation_terms, [])

    with {:ok, ranked} <-
           GraphServer.get_repo_map(
             graph_server,
             context_files,
             limit: limit,
             conversation_terms: conversation_terms
           ),
         {:ok, ranked_list} <- normalize_ranked(ranked, Keyword.get(opts, :min_rank, 0.0)) do
      {:ok, ranked_list}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Searches exported symbols across indexed files.
  """
  @spec find_symbols(String.t(), keyword()) :: {:ok, [ranked_symbol()]} | {:error, term()}
  def find_symbols(query, opts \\ []), do: Intelligence.find_symbols(query, opts)

  @doc """
  Matches indexed file paths with SQL LIKE style wildcards.
  """
  @spec match_files(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def match_files(pattern, opts \\ []), do: Intelligence.match_files(pattern, opts)

  @doc """
  Returns the direct blast radius count for a file.
  """
  @spec get_file_blast_radius(String.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, :graph_unavailable}
  def get_file_blast_radius(file, opts \\ []), do: Intelligence.blast_radius_count(file, opts)

  @doc """
  Finds exported functions with no external references.
  """
  @spec get_unused_exports(keyword()) :: {:ok, [unused_export()]} | {:error, term()}
  def get_unused_exports(opts \\ []), do: Intelligence.unused_exports(opts)

  @doc """
  Finds exported functions referenced only by tests.
  """
  @spec get_test_only_exports(keyword()) :: {:ok, [map()]} | {:error, term()}
  def get_test_only_exports(opts \\ []), do: Intelligence.test_only_exports(opts)

  @doc """
  Returns outbound and inbound dependencies for a file.
  """
  @spec get_module_deps(String.t(), keyword()) ::
          {:ok, %{dependencies: [String.t()], dependents: [String.t()]}} | {:error, term()}
  def get_module_deps(file, opts \\ []) do
    case fetch_graph(opts) do
      {:ok, graph} ->
        outgoing =
          graph
          |> Map.get(file, %{})
          |> Map.keys()
          |> Enum.uniq()
          |> Enum.sort()

        incoming =
          graph
          |> Enum.filter(fn {_from, out} -> Map.has_key?(out, file) end)
          |> Enum.map(fn {from, _} -> from end)
          |> Enum.uniq()
          |> Enum.sort()

        {:ok, %{dependencies: outgoing, dependents: incoming}}

      {:error, _reason} ->
        {:error, :graph_unavailable}
    end
  end

  @doc """
  Looks up symbols for a specific file.
  """
  @spec get_symbols(String.t(), keyword()) ::
          {:ok, [map()]} | {:error, :not_indexed} | {:error, term()}
  def get_symbols(file, opts \\ []) do
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())

    case backend.list_exported_symbols(repo_root, file) do
      {:ok, []} -> {:error, :not_indexed}
      other -> other
    end
  end

  @doc """
  Reindexes one file and invalidates graph cache.
  """
  @spec notify_file_changed(String.t(), keyword()) :: :ok | {:error, term()}
  def notify_file_changed(file, opts \\ []) do
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())

    with :ok <- backend.reindex_file(file, repo_root: repo_root) do
      GraphServer.mark_stale(GraphServer)
      :ok
    end
  end

  @doc """
  Returns a status snapshot for caller diagnostics.
  """
  @spec status() :: {:ok, status_snapshot()} | {:error, term()}
  def status do
    backend = Config.fetch(:backend)
    repo_root = Config.repo_root()

    graph =
      try do
        GraphServer.get_adjacency(GraphServer)
      rescue
        _ -> %{}
      end

    files = map_size(graph)

    case backend.index_status(repo_root) do
      {:ok, index_status} when index_status in [:ready, :stale, :missing, :error] ->
        case backend.healthy?(repo_root) do
          {:ok, backend_healthy} when is_boolean(backend_healthy) ->
            {:ok,
             %{
               backend: inspect(backend),
               dexter_db: Path.join(repo_root, Config.fetch(:dexter_db)),
               index_status: index_status,
               backend_healthy: backend_healthy,
               graph_stale: state_stale?(),
               files: files
             }}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :status_unavailable}
    end
  end

  defp fetch_graph(opts) do
    case Keyword.get(opts, :graph) do
      nil ->
        {:ok, GraphServer.get_adjacency(GraphServer)}

      graph when is_map(graph) ->
        {:ok, graph}

      graph when is_atom(graph) and graph != nil ->
        case pid_for(graph) do
          {:ok, pid} -> {:ok, GraphServer.get_adjacency(pid)}
          _ -> {:error, :graph_unavailable}
        end

      graph when is_pid(graph) ->
        {:ok, GraphServer.get_adjacency(graph)}

      _ ->
        {:error, :invalid_graph_source}
    end
  end

  defp state_stale? do
    case Process.whereis(GraphServer) do
      nil ->
        true

      pid ->
        case :sys.get_state(pid) do
          %{stale: stale} when is_boolean(stale) ->
            stale

          _ ->
            true
        end
    end
  end

  defp pid_for(graph) do
    case Process.whereis(graph) do
      nil -> {:error, :not_running}
      pid -> {:ok, pid}
    end
  end

  defp normalize_ranked(ranked, min_rank) do
    ranked = if is_map(ranked), do: Enum.to_list(ranked), else: ranked
    filtered = Enum.filter(ranked, fn {_file, rank} -> rank >= min_rank end)
    {:ok, filtered}
  end

  defp context_files(opts) do
    ([Keyword.get(opts, :active_file)] ++
       Keyword.get(opts, :mentioned_files, []) ++
       Keyword.get(opts, :edited_files, []))
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp fetch_symbols(backend, repo_root, ranked_files) do
    symbols =
      ranked_files
      |> Enum.reduce(%{}, fn {file, _score}, acc ->
        case backend.list_exported_symbols(repo_root, file) do
          {:ok, listed} -> Map.put(acc, file, listed)
          _ -> acc
        end
      end)

    {:ok, symbols}
  end

  defp fetch_metadata(graph_server) do
    {:ok, GraphServer.get_metadata(graph_server)}
  end

  defp fetch_summaries(ranked_files, metadata, symbols, repo_root, opts) do
    store_conn = store_conn(opts)
    summary_server = Keyword.get(opts, :summary_server, SummaryWorker)
    summary_enabled = Keyword.get(opts, :summary_enabled, Config.fetch(:summary_enabled))

    summaries =
      Map.new(ranked_files, fn {file, _score} ->
        metadata_for_file = Map.get(metadata, file)
        symbol_list = Map.get(symbols, file, [])

        case Metadata.summary_entry(metadata_for_file, symbol_list) do
          nil ->
            {file, nil}

          %{module_name: module_name, context: context, signature: signature} ->
            current_mtime = file_mtime(repo_root, file)

            case cached_summary(store_conn, file, module_name, current_mtime, signature) do
              {:ok, summary} ->
                {file, summary}

              :stale ->
                if summary_enabled do
                  SummaryWorker.summarize(
                    summary_server,
                    file,
                    module_name,
                    current_mtime,
                    context
                  )
                end

                {file, nil}
            end
        end
      end)

    {:ok, summaries}
  end

  defp cached_summary(nil, _file, _module_name, _current_mtime, _signature), do: :stale

  defp cached_summary(store_conn, file, module_name, current_mtime, signature) do
    case Store.get_summary(store_conn, file, module_name) do
      {:ok, {summary, cached_mtime, cached_signature}}
      when cached_mtime >= current_mtime and cached_signature == signature ->
        {:ok, summary}

      _ ->
        :stale
    end
  rescue
    _ -> :stale
  end

  defp detect_clones(ranked_files, metadata, true, opts) do
    threshold = Config.clone_similarity_threshold()
    store_conn = store_conn(opts)

    {clones, _seen} =
      Enum.reduce(ranked_files, {%{}, []}, fn {file, _score}, {clones_acc, seen} ->
        metadata_for_file = Map.get(metadata, file)
        module_name = Metadata.primary_module(metadata_for_file, file)
        tokens = Metadata.clone_tokens(metadata_for_file)

        persist_clone_signature(store_conn, file, module_name, metadata_for_file)

        if tokens == [] do
          {clones_acc, seen}
        else
          case best_clone_match(tokens, seen, threshold) do
            nil ->
              {clones_acc, [%{file: file, tokens: tokens} | seen]}

            %{source: source, similarity: similarity} ->
              {Map.put(clones_acc, file, %{source: source, similarity: similarity}),
               [%{file: file, tokens: tokens} | seen]}
          end
        end
      end)

    {:ok, clones}
  end

  defp detect_clones(_ranked_files, _metadata, false, _opts), do: {:ok, %{}}

  defp best_clone_match(tokens, seen, threshold) do
    seen
    |> Enum.map(fn %{file: source, tokens: other_tokens} ->
      %{source: source, similarity: jaccard_similarity(tokens, other_tokens)}
    end)
    |> Enum.filter(&(&1.similarity >= threshold))
    |> Enum.sort_by(fn %{similarity: similarity, source: source} -> {-similarity, source} end)
    |> List.first()
  end

  defp jaccard_similarity(left, right) do
    left = MapSet.new(left)
    right = MapSet.new(right)
    intersection = MapSet.intersection(left, right) |> MapSet.size()
    union = MapSet.union(left, right) |> MapSet.size()

    if union == 0 do
      0.0
    else
      intersection / union
    end
  end

  defp persist_clone_signature(nil, _file, _module_name, _metadata), do: :ok

  defp persist_clone_signature(store_conn, file, module_name, metadata) do
    case Metadata.clone_signature(metadata) do
      nil -> :ok
      signature -> Store.upsert_token_signature(store_conn, file, module_name, signature)
    end
  rescue
    _ -> :ok
  end

  defp store_conn(opts) do
    case Keyword.fetch(opts, :store_conn) do
      {:ok, conn} ->
        conn

      :error ->
        if Process.whereis(StoreServer) do
          StoreServer.conn()
        else
          nil
        end
    end
  end

  defp file_mtime(repo_root, file) do
    path = Path.join(repo_root, file)

    case File.stat(path, time: :posix) do
      {:ok, stat} -> stat.mtime
      _ -> 0
    end
  end

  defp clamp_budget(:auto, min, max, default, nil),
    do: clamp_budget(default, min, max, default, nil)

  defp clamp_budget(:auto, min, max, default, conversation_tokens)
       when is_integer(conversation_tokens) and conversation_tokens >= 1_000 do
    saturation = max(Config.fetch(:token_budget_saturation_tokens, 65_536), 1)
    scale = max(0.6, 1.0 - conversation_tokens / saturation * 0.4)
    budget = round(min + (max - min) * scale)
    clamp_budget(budget, min, max, default, nil)
  end

  defp clamp_budget(:auto, min, max, default, _conversation_tokens),
    do: clamp_budget(default, min, max, default, nil)

  defp clamp_budget(budget, min, max, _default, _conversation_tokens) when is_integer(budget) do
    min(max, max(min, budget))
  end

  defp clamp_budget(_, _min, _max, default, _conversation_tokens), do: default
end
