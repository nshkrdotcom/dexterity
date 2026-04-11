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
        strict: [repo_root: :string, backend: :string, depth: :integer, limit: :integer]
      )

    opts = elem(parsed, 0)
    args = elem(parsed, 1)

    if args == [] do
      Helpers.exit_with_error(
        "missing subcommand",
        "expected references|definition|blast|blast_count|cochanges|symbols|files|export_analysis|unused_exports|test_only_exports"
      )
    end

    [command | params] = args

    previous = [
      repo_root: Application.get_env(:dexterity, :repo_root),
      backend: Application.get_env(:dexterity, :backend)
    ]

    repo_root = Helpers.parse_repo_root(opts)
    backend = Helpers.parse_backend(opts)

    try do
      Application.put_env(:dexterity, :repo_root, repo_root)
      Application.put_env(:dexterity, :backend, backend)
      Helpers.ensure_started!()
      dispatch_command(command, params, opts)
    after
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
    Mix.shell().info("#{kind}: #{inspect(result, pretty: true, width: 80)}")
  end
end
