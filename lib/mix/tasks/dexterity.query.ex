defmodule Mix.Tasks.Dexterity.Query do
  @moduledoc """
  Dispatches Dexter query commands.

  Usage:
      mix dexterity.query references <module> [function] [arity]
      mix dexterity.query definition <module> [function] [arity]
      mix dexterity.query blast <file> [--depth N]
      mix dexterity.query blast_count <file>
      mix dexterity.query cochanges <file> [--limit N]
      mix dexterity.query symbols <query> [--limit N]
      mix dexterity.query files <sql_like_pattern> [--limit N]
      mix dexterity.query ranked_files [--active-file path] [--mentioned-file path] [--edited-file path]
                                     [--include-prefix path] [--exclude-prefix path]
                                     [--overscan-limit N] [--limit N] [--json]
      mix dexterity.query file_graph
      mix dexterity.query symbol_graph
      mix dexterity.query structural_snapshot [--include-export-analysis] [--include-runtime-observations]
      mix dexterity.query runtime_observations
      mix dexterity.query ranked_symbols [--active-file path] [--mentioned-file path]
      mix dexterity.query impact_context [--changed-file path] [--token-budget N]
      mix dexterity.query export_analysis [--limit N]
      mix dexterity.query unused_exports [--limit N]
      mix dexterity.query test_only_exports
  """

  use Mix.Task

  alias Dexterity
  alias Dexterity.GraphServer
  alias Dexterity.Query
  alias Mix.Tasks.Dexterity.TaskHelpers, as: Helpers

  @shortdoc "Runs Dexter queries"

  @impl Mix.Task
  def run(argv) do
    parsed =
      OptionParser.parse!(
        argv,
        strict: [
          repo_root: :string,
          backend: :string,
          dexter_bin: :string,
          depth: :integer,
          limit: :integer,
          json: :boolean,
          token_budget: :string,
          active_file: :string,
          mentioned_file: :keep,
          edited_file: :keep,
          include_prefix: :keep,
          exclude_prefix: :keep,
          overscan_limit: :integer,
          changed_file: :keep,
          include_export_analysis: :boolean,
          include_runtime_observations: :boolean
        ]
      )

    opts = elem(parsed, 0)
    args = elem(parsed, 1)

    if args == [] do
      Helpers.exit_with_error(
        "missing subcommand",
        "expected references|definition|blast|blast_count|cochanges|symbols|files|ranked_files|file_graph|symbol_graph|structural_snapshot|runtime_observations|ranked_symbols|impact_context|export_analysis|unused_exports|test_only_exports"
      )
    end

    [command | params] = args

    previous = [
      repo_root: Application.get_env(:dexterity, :repo_root),
      backend: Application.get_env(:dexterity, :backend),
      dexter_bin: Application.get_env(:dexterity, :dexter_bin)
    ]

    repo_root = Helpers.parse_repo_root(opts)
    backend = Helpers.parse_backend(opts)
    dexter_bin = Helpers.parse_dexter_bin(opts)

    try do
      Application.put_env(:dexterity, :repo_root, repo_root)
      Application.put_env(:dexterity, :backend, backend)
      Application.put_env(:dexterity, :dexter_bin, dexter_bin)
      Process.put({__MODULE__, :result_opts}, opts)
      Helpers.ensure_started!()
      dispatch_command(command, params, opts)
    after
      Process.delete({__MODULE__, :result_opts})

      Enum.each(previous, fn {key, value} ->
        if is_nil(value) do
          Application.delete_env(:dexterity, key)
        else
          Application.put_env(:dexterity, key, value)
        end
      end)
    end
  end

  defp dispatch_command("references", params, opts),
    do: run_query(&Query.find_references/4, params, opts, :references)

  defp dispatch_command("definition", params, opts),
    do: run_query(&Query.find_definition/4, params, opts, :definition)

  defp dispatch_command("blast", params, opts), do: run_blast(params, opts)
  defp dispatch_command("blast_count", params, opts), do: run_blast_count(params, opts)
  defp dispatch_command("cochanges", params, opts), do: run_cochanges(params, opts)
  defp dispatch_command("symbols", params, opts), do: run_symbol_search(params, opts)
  defp dispatch_command("files", params, opts), do: run_file_match(params, opts)
  defp dispatch_command("ranked_files", params, opts), do: run_ranked_files(params, opts)
  defp dispatch_command("file_graph", params, opts), do: run_file_graph(params, opts)
  defp dispatch_command("symbol_graph", params, opts), do: run_symbol_graph(params, opts)

  defp dispatch_command("structural_snapshot", params, opts),
    do: run_structural_snapshot(params, opts)

  defp dispatch_command("runtime_observations", params, opts),
    do: run_runtime_observations(params, opts)

  defp dispatch_command("ranked_symbols", params, opts), do: run_ranked_symbols(params, opts)
  defp dispatch_command("impact_context", params, opts), do: run_impact_context(params, opts)
  defp dispatch_command("export_analysis", params, opts), do: run_export_analysis(params, opts)
  defp dispatch_command("unused_exports", params, opts), do: run_unused_exports(params, opts)

  defp dispatch_command("test_only_exports", params, opts),
    do: run_test_only_exports(params, opts)

  defp dispatch_command(other, _params, _opts),
    do: Helpers.exit_with_error("unknown query command", other)

  defp run_query(fun, params, opts, kind) when length(params) in 1..3 do
    {module_name, function_name, arity} = query_params(params)
    query_opts = [backend: Helpers.parse_backend(opts), repo_root: Helpers.parse_repo_root(opts)]

    case fun.(module_name, function_name, arity, query_opts) do
      {:ok, result} ->
        render_query_result(kind, result)

      {:error, reason} ->
        Helpers.exit_with_error("#{kind} query failed", reason)
    end
  end

  defp run_query(_fun, params, _opts, kind) do
    Helpers.exit_with_error("#{kind} query requires at least 1 argument", params)
  end

  defp run_blast([], _opts), do: Helpers.exit_with_error("blast query requires file", nil)

  defp run_blast([file], opts) do
    query_opts = [
      graph_server: GraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts),
      depth: Helpers.parse_depth(opts, 2)
    ]

    case Query.blast_radius(file, query_opts) do
      {:ok, result} ->
        render_query_result(:blast_radius, result)

      {:error, reason} ->
        Helpers.exit_with_error("blast query failed", reason)
    end
  end

  defp run_blast(_params, _opts),
    do: Helpers.exit_with_error("blast query accepts exactly one file argument", nil)

  defp run_blast_count([], _opts),
    do: Helpers.exit_with_error("blast_count query requires file", nil)

  defp run_blast_count([file], opts) do
    query_opts = [
      graph_server: GraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts)
    ]

    case Dexterity.get_file_blast_radius(file, query_opts) do
      {:ok, result} ->
        render_query_result(:blast_count, result)

      {:error, reason} ->
        Helpers.exit_with_error("blast_count query failed", reason)
    end
  end

  defp run_blast_count(_params, _opts),
    do: Helpers.exit_with_error("blast_count query accepts exactly one file argument", nil)

  defp run_cochanges([], _opts), do: Helpers.exit_with_error("cochanges query requires file", nil)

  defp run_cochanges([file], opts) do
    limit = Helpers.parse_limit(opts)

    query_opts = [
      graph_server: GraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts),
      limit: limit
    ]

    case Query.cochanges(file, limit, query_opts) do
      {:ok, result} ->
        render_query_result(:cochanges, result)

      {:error, reason} ->
        Helpers.exit_with_error("cochanges query failed", reason)
    end
  end

  defp run_cochanges(_params, _opts),
    do: Helpers.exit_with_error("cochanges query accepts exactly one file argument", nil)

  defp run_symbol_search([], _opts),
    do: Helpers.exit_with_error("symbols query requires a search term", nil)

  defp run_symbol_search([query], opts) do
    query_opts = [
      graph_server: GraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts),
      limit: Helpers.parse_limit(opts)
    ]

    case Dexterity.find_symbols(query, query_opts) do
      {:ok, result} ->
        render_query_result(:symbols, result)

      {:error, reason} ->
        Helpers.exit_with_error("symbols query failed", reason)
    end
  end

  defp run_symbol_search(_params, _opts),
    do: Helpers.exit_with_error("symbols query accepts exactly one search term", nil)

  defp run_file_match([], _opts), do: Helpers.exit_with_error("files query requires pattern", nil)

  defp run_file_match([pattern], opts) do
    query_opts = [
      graph_server: GraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts),
      limit: Helpers.parse_limit(opts)
    ]

    case Dexterity.match_files(pattern, query_opts) do
      {:ok, result} ->
        render_query_result(:files, result)

      {:error, reason} ->
        Helpers.exit_with_error("files query failed", reason)
    end
  end

  defp run_file_match(_params, _opts),
    do: Helpers.exit_with_error("files query accepts exactly one pattern", nil)

  defp run_ranked_files([], opts) do
    query_opts = ranked_file_opts(opts)

    case Dexterity.get_ranked_files(query_opts) do
      {:ok, result} ->
        render_query_result(:ranked_files, result)

      {:error, reason} ->
        Helpers.exit_with_error("ranked_files query failed", reason)
    end
  end

  defp run_ranked_files(_params, _opts),
    do: Helpers.exit_with_error("ranked_files does not accept positional arguments", nil)

  defp run_file_graph([], opts) do
    query_opts = [
      graph_server: GraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts)
    ]

    case Dexterity.get_file_graph_snapshot(query_opts) do
      {:ok, result} ->
        render_query_result(:file_graph, result)

      {:error, reason} ->
        Helpers.exit_with_error("file_graph query failed", reason)
    end
  end

  defp run_file_graph(_params, _opts),
    do: Helpers.exit_with_error("file_graph does not accept positional arguments", nil)

  defp run_symbol_graph([], opts) do
    query_opts = [
      symbol_graph_server: Dexterity.SymbolGraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts)
    ]

    case Dexterity.get_symbol_graph_snapshot(query_opts) do
      {:ok, result} ->
        render_query_result(:symbol_graph, result)

      {:error, reason} ->
        Helpers.exit_with_error("symbol_graph query failed", reason)
    end
  end

  defp run_symbol_graph(_params, _opts),
    do: Helpers.exit_with_error("symbol_graph does not accept positional arguments", nil)

  defp run_structural_snapshot([], opts) do
    query_opts = [
      graph_server: GraphServer,
      symbol_graph_server: Dexterity.SymbolGraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts),
      include_export_analysis: Keyword.get(opts, :include_export_analysis, false),
      include_runtime_observations: Keyword.get(opts, :include_runtime_observations, false)
    ]

    case Dexterity.get_structural_snapshot(query_opts) do
      {:ok, result} ->
        render_query_result(:structural_snapshot, result)

      {:error, reason} ->
        Helpers.exit_with_error("structural_snapshot query failed", reason)
    end
  end

  defp run_structural_snapshot(_params, _opts),
    do: Helpers.exit_with_error("structural_snapshot does not accept positional arguments", nil)

  defp run_runtime_observations([], opts) do
    query_opts = [
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts)
    ]

    case Dexterity.get_runtime_observations(query_opts) do
      {:ok, result} ->
        render_query_result(:runtime_observations, result)

      {:error, reason} ->
        Helpers.exit_with_error("runtime_observations query failed", reason)
    end
  end

  defp run_runtime_observations(_params, _opts),
    do: Helpers.exit_with_error("runtime_observations does not accept positional arguments", nil)

  defp run_ranked_symbols([], opts) do
    query_opts = ranked_symbol_opts(opts)

    case Dexterity.get_ranked_symbols(query_opts) do
      {:ok, result} ->
        render_query_result(:ranked_symbols, result)

      {:error, reason} ->
        Helpers.exit_with_error("ranked_symbols query failed", reason)
    end
  end

  defp run_ranked_symbols(_params, _opts),
    do: Helpers.exit_with_error("ranked_symbols does not accept positional arguments", nil)

  defp run_impact_context([], opts) do
    query_opts =
      opts
      |> ranked_symbol_opts()
      |> Keyword.put(:changed_files, Helpers.parse_file_list(opts, :changed_file))
      |> Keyword.put(:token_budget, Helpers.parse_token_budget(opts))

    case Dexterity.get_impact_context(query_opts) do
      {:ok, result} ->
        render_query_result(:impact_context, result)

      {:error, reason} ->
        Helpers.exit_with_error("impact_context query failed", reason)
    end
  end

  defp run_impact_context(_params, _opts),
    do: Helpers.exit_with_error("impact_context does not accept positional arguments", nil)

  defp run_export_analysis([], opts) do
    query_opts = [
      graph_server: GraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts),
      limit: Helpers.parse_limit(opts)
    ]

    case Dexterity.get_export_analysis(query_opts) do
      {:ok, result} ->
        render_query_result(:export_analysis, result)

      {:error, reason} ->
        Helpers.exit_with_error("export_analysis query failed", reason)
    end
  end

  defp run_export_analysis(_params, _opts),
    do: Helpers.exit_with_error("export_analysis does not accept positional arguments", nil)

  defp run_unused_exports([], opts) do
    query_opts = [
      graph_server: GraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts),
      limit: Helpers.parse_limit(opts)
    ]

    case Dexterity.get_unused_exports(query_opts) do
      {:ok, result} ->
        render_query_result(:unused_exports, result)

      {:error, reason} ->
        Helpers.exit_with_error("unused_exports query failed", reason)
    end
  end

  defp run_unused_exports(_params, _opts),
    do: Helpers.exit_with_error("unused_exports does not accept positional arguments", nil)

  defp run_test_only_exports([], opts) do
    query_opts = [
      graph_server: GraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts)
    ]

    case Dexterity.get_test_only_exports(query_opts) do
      {:ok, result} ->
        render_query_result(:test_only_exports, result)

      {:error, reason} ->
        Helpers.exit_with_error("test_only_exports query failed", reason)
    end
  end

  defp run_test_only_exports(_params, _opts),
    do: Helpers.exit_with_error("test_only_exports does not accept positional arguments", nil)

  defp ranked_symbol_opts(opts) do
    [
      graph_server: GraphServer,
      symbol_graph_server: Dexterity.SymbolGraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts),
      limit: Helpers.parse_limit(opts),
      active_file: Keyword.get(opts, :active_file),
      mentioned_files: Helpers.parse_file_list(opts, :mentioned_file),
      edited_files: Helpers.parse_file_list(opts, :edited_file)
    ]
  end

  defp ranked_file_opts(opts) do
    [
      graph_server: GraphServer,
      backend: Helpers.parse_backend(opts),
      repo_root: Helpers.parse_repo_root(opts),
      limit: Helpers.parse_limit(opts),
      active_file: Keyword.get(opts, :active_file),
      mentioned_files: Helpers.parse_file_list(opts, :mentioned_file),
      edited_files: Helpers.parse_file_list(opts, :edited_file),
      include_prefixes: Helpers.parse_file_list(opts, :include_prefix),
      exclude_prefixes: Helpers.parse_file_list(opts, :exclude_prefix),
      overscan_limit: Keyword.get(opts, :overscan_limit)
    ]
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] or value == [] end)
  end

  defp query_params([module_name]), do: {module_name, nil, nil}
  defp query_params([module_name, function_name]), do: {module_name, function_name, nil}

  defp query_params([module_name, function_name, arity]) do
    {module_name, function_name, parse_arity(arity)}
  end

  defp parse_arity(value) do
    case Integer.parse(to_string(value)) do
      {arity, ""} -> arity
      _ -> Helpers.exit_with_error("invalid arity", value)
    end
  end

  defp render_query_result(kind, result) do
    if Keyword.get(result_opts(), :json, false) do
      Mix.shell().info(
        Jason.encode!(%{
          ok: true,
          command: to_string(kind),
          result: normalize_json(result)
        })
      )
    else
      Mix.shell().info("#{kind}: #{inspect(result, pretty: true, width: 80)}")
    end
  end

  defp result_opts do
    Process.get({__MODULE__, :result_opts}, [])
  end

  defp normalize_json(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), normalize_json(value)} end)
  end

  defp normalize_json(list) when is_list(list) do
    Enum.map(list, &normalize_json/1)
  end

  defp normalize_json(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> normalize_json()
  end

  defp normalize_json(other), do: other
end
