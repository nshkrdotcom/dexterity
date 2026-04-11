defmodule Dexterity.ExportAnalysis do
  @moduledoc false

  alias Dexterity.AnalysisSupport
  alias Dexterity.Config
  alias Dexterity.Entrypoints
  alias Dexterity.Store
  alias Dexterity.StoreServer

  @type export_kind :: :callback_entrypoint | :public_api
  @type reachability :: :callback | :internal_only | :production | :runtime | :test_only | :unused

  @type export_analysis :: %{
          module: String.t(),
          function: String.t(),
          arity: non_neg_integer(),
          file: String.t(),
          line: non_neg_integer(),
          kind: export_kind(),
          reachability: reachability(),
          used_internally: boolean(),
          prod_ref_count: non_neg_integer(),
          test_ref_count: non_neg_integer(),
          same_file_ref_count: non_neg_integer(),
          runtime_call_count: non_neg_integer(),
          runtime_sources: [String.t()],
          entrypoint_sources: [String.t()]
        }

  @type unused_export :: %{
          module: String.t(),
          function: String.t(),
          arity: non_neg_integer(),
          file: String.t(),
          line: non_neg_integer(),
          used_internally: boolean()
        }

  @type runtime_observation_input ::
          %{
            required(:module) => String.t() | module(),
            required(:function) => String.t() | atom(),
            required(:arity) => non_neg_integer(),
            optional(:call_count) => non_neg_integer(),
            optional(:source) => String.t()
          }

  @spec analyze_exports(keyword()) :: {:ok, [export_analysis()]} | {:error, term()}
  def analyze_exports(opts \\ []) do
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    graph_server = Keyword.get(opts, :graph_server, Dexterity.GraphServer)
    limit = Keyword.get(opts, :limit, 500)
    baseline = AnalysisSupport.baseline_rank(graph_server)
    metadata = AnalysisSupport.metadata_map(backend, repo_root, graph_server)
    runtime_observations = runtime_observation_map(store_conn(opts))

    with {:ok, symbols} <- AnalysisSupport.collect_symbols(backend, repo_root) do
      symbols
      |> Enum.reject(&AnalysisSupport.test_path?(&1.file))
      |> Enum.reduce_while({:ok, []}, fn symbol, {:ok, acc} ->
        case analyze_symbol(symbol, backend, repo_root, metadata, runtime_observations) do
          {:ok, export} ->
            {:cont, {:ok, [Map.put(export, :rank, Map.get(baseline, export.file, 0.0)) | acc]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> then(fn
        {:ok, analysis} ->
          analysis
          |> Enum.sort_by(fn export ->
            {-Map.get(export, :rank, 0.0), export.file, export.line, export.function}
          end)
          |> Enum.take(limit)
          |> Enum.map(&Map.delete(&1, :rank))
          |> then(&{:ok, &1})

        error ->
          error
      end)
    end
  end

  @spec unused_exports(keyword()) :: {:ok, [unused_export()]} | {:error, term()}
  def unused_exports(opts \\ []) do
    with {:ok, analysis} <- analyze_exports(opts) do
      analysis
      |> Enum.filter(fn export -> export.reachability in [:internal_only, :unused] end)
      |> Enum.map(&unused_export_from_analysis/1)
      |> then(&{:ok, &1})
    end
  end

  @spec test_only_exports(keyword()) :: {:ok, [map()]} | {:error, term()}
  def test_only_exports(opts \\ []) do
    with {:ok, analysis} <- analyze_exports(opts) do
      analysis
      |> Enum.filter(&(&1.reachability == :test_only))
      |> Enum.map(fn export ->
        Map.take(export, [:module, :function, :arity, :file, :line])
      end)
      |> then(&{:ok, &1})
    end
  end

  @spec record_runtime_observations(
          runtime_observation_input() | [runtime_observation_input()],
          keyword()
        ) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def record_runtime_observations(observations, opts \\ []) do
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    now = System.os_time(:second)

    with {:ok, normalized} <- normalize_observations(observations),
         {:ok, conn} <- require_store_conn(store_conn(opts)),
         {:ok, symbols} <- AnalysisSupport.collect_symbols(backend, repo_root) do
      symbol_index = Map.new(symbols, fn symbol -> {symbol_key(symbol), symbol} end)

      Enum.reduce_while(normalized, {:ok, 0}, fn observation, {:ok, recorded} ->
        case Map.get(symbol_index, symbol_key(observation)) do
          nil ->
            {:cont, {:ok, recorded}}

          symbol ->
            case Store.upsert_runtime_observation(
                   conn,
                   symbol.file,
                   symbol.module,
                   symbol.function,
                   symbol.arity,
                   observation.source,
                   observation.call_count,
                   now
                 ) do
              :ok ->
                {:cont, {:ok, recorded + 1}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
        end
      end)
    end
  end

  @spec import_cover_modules(module() | [module()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def import_cover_modules(modules, opts \\ []) do
    with :ok <- ensure_cover_available(),
         {:ok, normalized_modules} <- normalize_modules(modules),
         {:ok, observations} <- cover_observations(normalized_modules) do
      record_runtime_observations(observations, opts)
    end
  end

  defp analyze_symbol(symbol, backend, repo_root, metadata, runtime_observations) do
    case backend.find_references(repo_root, symbol.module, symbol.function, symbol.arity) do
      {:ok, refs} ->
        {same_file_refs, external_refs} =
          Enum.split_with(refs, fn ref -> ref.file == symbol.file end)

        {test_refs, prod_refs} =
          Enum.split_with(external_refs, &AnalysisSupport.test_path?(&1.file))

        entrypoint = Entrypoints.classify(symbol, Map.get(metadata, symbol.file, %{}))

        runtime = Map.get(runtime_observations, symbol_key(symbol), %{call_count: 0, sources: []})

        {:ok,
         %{
           module: symbol.module,
           function: symbol.function,
           arity: symbol.arity,
           file: symbol.file,
           line: symbol.line,
           kind: entrypoint.kind,
           reachability:
             reachability(
               prod_refs,
               entrypoint.implicit_refs,
               runtime.call_count,
               test_refs,
               same_file_refs
             ),
           used_internally: same_file_refs != [],
           prod_ref_count: length(prod_refs),
           test_ref_count: length(test_refs),
           same_file_ref_count: length(same_file_refs),
           runtime_call_count: runtime.call_count,
           runtime_sources: runtime.sources,
           entrypoint_sources: Enum.map(entrypoint.implicit_refs, & &1.source)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reachability(prod_refs, implicit_refs, runtime_call_count, test_refs, same_file_refs) do
    cond do
      prod_refs != [] -> :production
      implicit_refs != [] -> :callback
      runtime_call_count > 0 -> :runtime
      test_refs != [] -> :test_only
      same_file_refs != [] -> :internal_only
      true -> :unused
    end
  end

  defp runtime_observation_map(nil), do: %{}

  defp runtime_observation_map(conn) do
    case Store.list_runtime_observations(conn) do
      {:ok, observations} ->
        Enum.reduce(observations, %{}, fn observation, acc ->
          Map.update(
            acc,
            {observation.module, observation.function, observation.arity},
            %{call_count: observation.call_count, sources: [observation.source]},
            fn existing ->
              %{
                call_count: existing.call_count + observation.call_count,
                sources: Enum.sort(Enum.uniq([observation.source | existing.sources]))
              }
            end
          )
        end)

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp normalize_observations(observations) when is_list(observations) do
    observations
    |> Enum.reduce_while({:ok, []}, fn observation, {:ok, acc} ->
      case normalize_observation(observation) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end)
  end

  defp normalize_observations(observation), do: normalize_observations([observation])

  defp normalize_observation(%{module: module, function: function, arity: arity} = observation)
       when is_integer(arity) and arity >= 0 do
    {:ok,
     %{
       module: normalize_module_name(module),
       function: normalize_function_name(function),
       arity: arity,
       call_count: max(Map.get(observation, :call_count, 1), 1),
       source: Map.get(observation, :source, "runtime")
     }}
  end

  defp normalize_observation(_observation), do: {:error, :invalid_runtime_observation}

  defp normalize_modules(module) when is_atom(module), do: {:ok, [module]}

  defp normalize_modules(modules) when is_list(modules) do
    modules
    |> Enum.filter(&is_atom/1)
    |> case do
      [] -> {:error, :invalid_modules}
      atoms -> {:ok, atoms}
    end
  end

  defp normalize_modules(_modules), do: {:error, :invalid_modules}

  defp cover_observations(modules) do
    modules
    |> Enum.reduce_while({:ok, []}, fn module, {:ok, acc} ->
      case cover_apply(:analyse, [module, :calls, :function]) do
        {:ok, rows} ->
          observations =
            Enum.flat_map(rows, fn
              {{^module, function, arity}, call_count} when call_count > 0 ->
                [
                  %{
                    module: module,
                    function: function,
                    arity: arity,
                    call_count: call_count,
                    source: "cover"
                  }
                ]

              _ ->
                []
            end)

          {:cont, {:ok, acc ++ observations}}

        error ->
          {:halt, normalize_cover_error(error)}
      end
    end)
  end

  defp ensure_cover_available do
    case cover_ebin_path() do
      nil -> :ok
      tools_ebin -> :code.add_pathz(String.to_charlist(tools_ebin))
    end

    case :code.ensure_loaded(:cover) do
      {:module, :cover} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_cover_error({:error, reason}), do: {:error, reason}
  defp normalize_cover_error(other), do: {:error, other}

  defp cover_apply(function_name, args) do
    :erlang.apply(:cover, function_name, args)
  end

  defp cover_ebin_path do
    otp_root = to_string(:code.root_dir())

    otp_root
    |> Path.join("lib/tools-*/ebin")
    |> Path.wildcard()
    |> Enum.sort()
    |> List.first()
  end

  defp normalize_module_name(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp normalize_module_name(module) when is_binary(module) do
    String.trim_leading(module, "Elixir.")
  end

  defp normalize_function_name(function) when is_atom(function), do: Atom.to_string(function)
  defp normalize_function_name(function) when is_binary(function), do: function

  defp unused_export_from_analysis(export) do
    Map.take(export, [:module, :function, :arity, :file, :line, :used_internally])
  end

  defp symbol_key(%{module: module, function: function, arity: arity}),
    do: {module, function, arity}

  defp require_store_conn(nil), do: {:error, :store_unavailable}
  defp require_store_conn(conn), do: {:ok, conn}

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
end
