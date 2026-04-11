defmodule Mix.Tasks.Dexterity.Query do
  @moduledoc """
  Dispatches Dexter query commands.

  Usage:
      mix dexterity.query references <module> [function] [arity]
      mix dexterity.query definition <module> [function] [arity]
      mix dexterity.query blast <file> [--depth N]
      mix dexterity.query cochanges <file> [--limit N]
  """

  use Mix.Task

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
        "expected references|definition|blast|cochanges"
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

      case command do
        "references" ->
          run_query(&Query.find_references/4, params, opts, :references)

        "definition" ->
          run_query(&Query.find_definition/4, params, opts, :definition)

        "blast" ->
          run_blast(params, opts)

        "cochanges" ->
          run_cochanges(params, opts)

        other ->
          Helpers.exit_with_error("unknown query command", other)
      end
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
