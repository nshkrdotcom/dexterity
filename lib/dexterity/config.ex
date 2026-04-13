defmodule Dexterity.Config do
  @moduledoc false

  @default_config [
    repo_root: Path.expand("."),
    dexter_db: ".dexter.db",
    store_path: {:project_relative, ".dexterity/dexterity.db"},
    dexter_bin: "dexter",
    backend: Dexterity.Backend.Dexter,
    pagerank_iterations: 20,
    pagerank_damping: 0.85,
    pagerank_uniform_baseline: 0.70,
    pagerank_context_boost: 0.30,
    default_token_budget: 8192,
    min_token_budget: 2048,
    max_token_budget: 8192,
    token_budget_saturation_tokens: 65_536,
    include_clones: true,
    min_rank: 0.0,
    cochange_commit_depth: 500,
    cochange_min_frequency: 3,
    cochange_interval_ms: 30 * 60 * 1000,
    watch_debounce_ms: 200,
    cochange_enabled: true,
    summary_enabled: false,
    summary_signature_threshold: 0.85,
    clone_similarity_threshold: 0.90,
    server_call_timeout: :infinity,
    token_model: "gpt-4",
    mcp_enabled: false
  ]

  @type key :: atom()

  @doc """
  Returns a merged Dexterity config map.
  """
  @spec all() :: map()
  def all do
    app = Application.get_all_env(:dexterity)

    @default_config
    |> Keyword.merge(app)
    |> Enum.into(%{})
  end

  @doc """
  Returns a single config key with a default fallback.
  """
  @spec fetch(key(), term()) :: term()
  def fetch(key, default \\ nil), do: Map.get(all(), key, default)

  @doc """
  Allows tests to mutate configuration.
  """
  @spec put(key(), term()) :: :ok
  def put(key, value) when is_atom(key) do
    Application.put_env(:dexterity, key, value)
    :ok
  end

  @doc """
  Returns the repository root used by Dexterity.
  """
  @spec repo_root() :: String.t()
  def repo_root do
    fetch(:repo_root) |> Path.expand()
  end

  @doc """
  Returns the path to `.dexter.db` for the repo.
  """
  @spec dexter_db_path() :: String.t()
  def dexter_db_path do
    Path.join(repo_root(), fetch(:dexter_db))
  end

  @doc """
  Returns the path to Dexterity metadata db.
  """
  @spec store_path() :: String.t()
  def store_path do
    case fetch(:store_path) do
      {:project_relative, rel} ->
        Path.join(repo_root(), rel)

      path when is_binary(path) ->
        Path.expand(path)

      other ->
        raise ArgumentError, "invalid store_path config value: #{inspect(other)}"
    end
  end

  @doc """
  Returns the active backend module.
  """
  @spec backend() :: module()
  def backend do
    fetch(:backend)
  end

  @doc """
  Returns the configured dexter CLI executable path.
  """
  @spec dexter_bin() :: String.t()
  def dexter_bin do
    fetch(:dexter_bin)
  end

  @doc """
  Returns token budget settings.
  """
  @spec token_budget_range() :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def token_budget_range do
    {
      fetch(:min_token_budget),
      fetch(:default_token_budget),
      fetch(:max_token_budget)
    }
  end

  @doc """
  Returns the active token model.
  """
  @spec token_model() :: String.t()
  def token_model do
    fetch(:token_model)
  end

  @doc """
  Returns the co-change feature interval in milliseconds.
  """
  @spec cochange_interval_ms() :: non_neg_integer()
  def cochange_interval_ms do
    fetch(:cochange_interval_ms)
  end

  @doc """
  Returns whether co-change analysis is enabled.
  """
  @spec cochange_enabled?() :: boolean()
  def cochange_enabled? do
    fetch(:cochange_enabled, false)
  end

  @doc """
  Returns the clone similarity threshold.
  """
  @spec clone_similarity_threshold() :: float()
  def clone_similarity_threshold do
    fetch(:clone_similarity_threshold)
  end
end
