defmodule Dexterity do
  @moduledoc """
  Core public API for Dexterity.
  """

  alias Dexterity.Config
  alias Dexterity.GraphServer
  alias Dexterity.Render

  @type context_opts :: [
          active_file: String.t(),
          mentioned_files: [String.t()],
          edited_files: [String.t()],
          token_budget: pos_integer() | :auto,
          include_clones: boolean(),
          min_rank: float(),
          limit: pos_integer(),
          backend: module(),
          repo_root: String.t()
        ]

  @type status_snapshot :: %{
          backend: String.t(),
          dexter_db: String.t(),
          index_status: atom(),
          backend_healthy: boolean(),
          graph_stale: boolean(),
          files: non_neg_integer()
        }

  @doc """
  Returns ranked and rendered repository context.
  """
  @spec get_repo_map(context_opts()) :: {:ok, String.t()} | {:error, term()}
  def get_repo_map(opts \\ []) do
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    budget = Keyword.get(opts, :token_budget, :auto)
    {min_budget, default_budget, max_budget} = Config.token_budget_range()
    budget = clamp_budget(budget, min_budget, max_budget, default_budget)
    limit = Keyword.get(opts, :limit, 25)
    include_clones = Keyword.get(opts, :include_clones, Config.fetch(:include_clones))

    context_files = context_files(opts)

    with {:ok, ranked} <- GraphServer.get_repo_map(GraphServer, context_files, limit: limit),
         {:ok, ranked_list} <- normalize_ranked(ranked, Keyword.get(opts, :min_rank, 0.0)),
         {:ok, symbols} <- fetch_symbols(backend, repo_root, ranked_list),
         {:ok, summaries} <- fetch_summaries(ranked_list),
         {:ok, clones} <- detect_clones(ranked_list, include_clones) do
      {:ok, Render.render_files(ranked_list, symbols, summaries, clones, budget)}
    end
  end

  @doc """
  Returns ranked files ordered by relevance.
  """
  @spec get_ranked_files(context_opts()) :: {:ok, [{String.t(), float()}]} | {:error, term()}
  def get_ranked_files(opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    context_files = context_files(opts)

    with {:ok, ranked} <- GraphServer.get_repo_map(GraphServer, context_files, limit: limit),
         {:ok, ranked_list} <- normalize_ranked(ranked, Keyword.get(opts, :min_rank, 0.0)) do
      {:ok, ranked_list}
    else
      {:error, reason} -> {:error, reason}
    end
  end

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
    ([Keyword.get(opts, :active_file)] ++ Keyword.get(opts, :mentioned_files, []) ++
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

  defp fetch_summaries(ranked_files) do
    {:ok, Enum.into(ranked_files, %{}, fn {file, _score} -> {file, nil} end)}
  end

  defp detect_clones(ranked_files, true) do
    {:ok, Map.new(ranked_files, fn {file, _score} -> {file, nil} end)}
  end

  defp detect_clones(_ranked_files, false), do: {:ok, %{}}

  defp clamp_budget(:auto, _, _, default), do: default

  defp clamp_budget(budget, min, max, _) when is_integer(budget) do
    min(max, max(min, budget))
  end

  defp clamp_budget(_, _, _, default), do: default
end
