defmodule Dexterity.MCP do
  @moduledoc """
  Deterministic JSON-RPC/MCP transport over stdio.
  """
  alias Dexterity.{Config, GraphServer, Query, SymbolGraphServer}

  @jsonrpc "2.0"
  @parse_error -32_700
  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @internal_error -32_603

  @supported_tools [
    {"query_references", "Find all references for a symbol"},
    {"query_definition", "Find symbol definitions"},
    {"query_blast", "Find blast radius"},
    {"query_cochanges", "Find file co-change neighbors"},
    {"find_symbols", "Search exported symbols across indexed files"},
    {"match_files", "Match indexed file paths with SQL LIKE wildcards"},
    {"get_file_blast_radius", "Count direct dependents for a file"},
    {"get_ranked_files", "Get ranked files list"},
    {"get_ranked_symbols", "Get ranked symbols list"},
    {"get_impact_context", "Get rendered impact context for changed symbols/files"},
    {"get_repo_map", "Get rendered ranked repo map"},
    {"get_symbols", "Get exported symbols for a file"},
    {"get_export_analysis", "Get full export reachability analysis"},
    {"get_unused_exports", "Find exports with no external references"},
    {"get_test_only_exports", "Find exports referenced only by tests"},
    {"get_module_deps", "Get module dependencies"},
    {"status", "Get runtime status snapshot"}
  ]

  @type runtime_context :: %{
          backend: module(),
          repo_root: String.t(),
          graph_server: module(),
          symbol_graph_server: module()
        }

  @spec serve(keyword()) :: :ok
  def serve(opts \\ []) do
    context = %{
      backend: Keyword.get(opts, :backend, Config.fetch(:backend)),
      repo_root: Keyword.get(opts, :repo_root, Config.repo_root()),
      graph_server: Keyword.get(opts, :graph_server, GraphServer),
      symbol_graph_server: Keyword.get(opts, :symbol_graph_server, SymbolGraphServer)
    }

    :stdio
    |> IO.stream(:line)
    |> Stream.each(fn line ->
      line
      |> String.trim()
      |> process_line(context)
    end)
    |> Stream.run()
  end

  @spec handle_request(map(), runtime_context()) ::
          {:ok, map()} | {:error, map()}
  def handle_request(%{"jsonrpc" => @jsonrpc, "method" => method} = request, context)
      when is_binary(method) do
    id = Map.get(request, "id")
    params = Map.get(request, "params", %{})

    try do
      case dispatch(method, params, context) do
        {:ok, result} ->
          {:ok, response(id, result)}

        {:error, code, message, data} ->
          {:ok, error_response(id, code, message, data)}
      end
    rescue
      e in ArgumentError ->
        {:ok, error_response(id, @invalid_params, "invalid params", Exception.message(e))}

      error ->
        {:ok, error_response(id, @internal_error, "internal error", Exception.message(error))}
    end
  end

  def handle_request(%{} = request, _context) when map_size(request) == 0 do
    {:error, error_payload(nil, @invalid_request, "invalid request", "request body is empty")}
  end

  def handle_request(request, _context) do
    {:error,
     error_payload(
       Map.get(request, :id) || Map.get(request, "id"),
       @invalid_request,
       "invalid request",
       "jsonrpc 2.0 required"
     )}
  end

  @spec process_line(String.t(), runtime_context()) :: :ok
  def process_line("", _context), do: :ok

  def process_line(line, context) do
    line = String.trim(line)

    case parse_request(line) do
      {:ok, request} ->
        request
        |> handle_request(context)
        |> encode_and_print()

      {:error, reason} ->
        {:error, error_payload(nil, @parse_error, "parse error", reason)}
        |> encode_and_print()
    end
  end

  @spec tools() :: [map()]
  def tools do
    Enum.map(@supported_tools, fn {name, description} ->
      %{
        "name" => name,
        "description" => description,
        "inputSchema" => %{
          type: "object",
          properties: %{},
          required: []
        }
      }
    end)
  end

  defp parse_request(line) do
    case Jason.decode(line) do
      {:ok, request} when is_map(request) ->
        {:ok, request}

      {:ok, _} ->
        {:error, "payload must be a JSON object"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp parse_tool_args(params) when is_map(params), do: params
  defp parse_tool_args(_), do: %{}

  defp dispatch("initialize", params, _context) do
    client_info = Map.get(parse_tool_args(params), "info", "anonymous")

    {:ok,
     %{
       "protocolVersion" => @jsonrpc,
       "serverName" => "dexterity",
       "clientInfo" => client_info,
       "capabilities" => %{"tools" => true},
       "version" => Application.spec(:dexterity, :vsn) || "0.1.0"
     }}
  end

  defp dispatch("tools/list", _params, _context) do
    {:ok, %{"tools" => tools()}}
  end

  defp dispatch("tools/call", params, context) do
    arguments = parse_tool_args(params)
    tool_name = arguments["name"] || arguments[:name]
    tool_args = arguments["arguments"] || arguments[:arguments] || %{}

    case tool_name do
      nil ->
        {:error, @invalid_params, "invalid params", "tools/call requires name"}

      _name ->
        dispatch_tool(tool_name, tool_args, context)
    end
  end

  defp dispatch("shutdown", _params, _context) do
    exit(:normal)
  end

  defp dispatch(method, _params, _context) do
    {:error, @method_not_found, "method not found", "unsupported method #{method}"}
  end

  defp dispatch_tool("query_references", params, context),
    do: begin_query_tool(params, context, &Query.find_references/4)

  defp dispatch_tool("query_definition", params, context),
    do: begin_query_tool(params, context, &Query.find_definition/4)

  defp dispatch_tool("query_blast", params, context) do
    file = get_required(params, "file")
    query_opts = query_opts(params, context)
    depth = parse_integer(get_optional(params, "depth"), fallback: 2)

    Query.blast_radius(file, Keyword.put(query_opts, :depth, depth))
    |> call_result()
  end

  defp dispatch_tool("query_cochanges", params, context) do
    file = get_required(params, "file")
    limit = parse_integer(get_optional(params, "limit"), fallback: 10)
    query_opts = query_opts(params, context)

    Query.cochanges(file, limit, query_opts)
    |> call_result()
  end

  defp dispatch_tool("find_symbols", params, context) do
    query = get_required(params, "query")
    limit = parse_integer(get_optional(params, "limit"), fallback: 10)
    opts = Keyword.put(analysis_opts(params, context), :limit, limit)

    Elixir.Dexterity.find_symbols(query, opts)
    |> call_result()
  end

  defp dispatch_tool("match_files", params, context) do
    pattern = get_required(params, "pattern")
    limit = parse_integer(get_optional(params, "limit"), fallback: 20)
    opts = Keyword.put(analysis_opts(params, context), :limit, limit)

    Elixir.Dexterity.match_files(pattern, opts)
    |> call_result()
  end

  defp dispatch_tool("get_file_blast_radius", params, context) do
    file = get_required(params, "file")

    Elixir.Dexterity.get_file_blast_radius(file, analysis_opts(params, context))
    |> call_result()
  end

  defp dispatch_tool("get_ranked_files", params, context) do
    opts = map_query_opts(params, context)

    Elixir.Dexterity.get_ranked_files(opts)
    |> call_result()
  end

  defp dispatch_tool("get_ranked_symbols", params, context) do
    opts = map_query_opts(params, context)

    Elixir.Dexterity.get_ranked_symbols(opts)
    |> call_result()
  end

  defp dispatch_tool("get_impact_context", params, context) do
    changed_files =
      parse_file_list(
        get_optional(params, "changed_files") || get_optional(params, "changedFiles")
      )

    opts =
      params
      |> map_query_opts(context)
      |> Keyword.put(:changed_files, changed_files)
      |> Keyword.put(
        :token_budget,
        parse_integer(get_optional(params, "token_budget"), fallback: 2_048)
      )

    Elixir.Dexterity.get_impact_context(opts)
    |> call_result()
  end

  defp dispatch_tool("get_repo_map", params, context) do
    opts = map_query_opts(params, context)
    token_budget = parse_integer(get_optional(params, "token_budget"), fallback: :auto)
    opts = Keyword.put(opts, :token_budget, token_budget)

    Elixir.Dexterity.get_repo_map(opts)
    |> call_result()
  end

  defp dispatch_tool("get_symbols", params, context) do
    file = get_required(params, "file")
    opts = tool_opts(params, context)

    Elixir.Dexterity.get_symbols(file, opts)
    |> call_result()
  end

  defp dispatch_tool("get_export_analysis", params, context) do
    limit = parse_integer(get_optional(params, "limit"), fallback: 500)
    opts = Keyword.put(analysis_opts(params, context), :limit, limit)

    Elixir.Dexterity.get_export_analysis(opts)
    |> call_result()
  end

  defp dispatch_tool("get_unused_exports", params, context) do
    limit = parse_integer(get_optional(params, "limit"), fallback: 500)
    opts = Keyword.put(analysis_opts(params, context), :limit, limit)

    Elixir.Dexterity.get_unused_exports(opts)
    |> call_result()
  end

  defp dispatch_tool("get_test_only_exports", params, context) do
    Elixir.Dexterity.get_test_only_exports(analysis_opts(params, context))
    |> call_result()
  end

  defp dispatch_tool("get_module_deps", params, context) do
    file = get_required(params, "file")
    opts = tool_opts(params, context)

    Elixir.Dexterity.get_module_deps(file, opts)
    |> call_result()
  end

  defp dispatch_tool("status", _params, _context) do
    Elixir.Dexterity.status()
    |> call_result()
  end

  defp dispatch_tool(name, _params, _context),
    do: {:error, @method_not_found, "method not found", "tool #{name} is unknown"}

  defp begin_query_tool(params, context, query_fun) do
    module_name = get_required(params, "module")
    function_name = get_optional(params, "function")
    arity = parse_arity(get_optional(params, "arity"))
    query_opts = query_opts(params, context)

    query_fun.(module_name, function_name, arity, query_opts)
    |> call_result()
  end

  defp call_result({:ok, result}), do: {:ok, %{"result" => result}}

  defp call_result({:error, reason}),
    do: {:error, @invalid_params, "request failed", inspect(reason)}

  defp tool_opts(params, context) do
    repo_root = get_optional(params, "repo_root") || context.repo_root
    backend = safe_module(get_optional(params, "backend"), context.backend)

    [repo_root: repo_root, backend: backend]
  end

  defp analysis_opts(params, context) do
    tool_opts(params, context)
    |> Keyword.put(:graph_server, context.graph_server)
    |> Keyword.put(
      :symbol_graph_server,
      Map.get(context, :symbol_graph_server, SymbolGraphServer)
    )
  end

  defp map_query_opts(params, context) do
    active_file = get_optional(params, "active_file") || get_optional(params, "activeFile")

    mentioned_files =
      parse_file_list(
        get_optional(params, "mentioned_files") || get_optional(params, "mentionedFiles")
      )

    edited_files =
      parse_file_list(get_optional(params, "edited_files") || get_optional(params, "editedFiles"))

    conversation_terms =
      parse_file_list(
        get_optional(params, "conversation_terms") || get_optional(params, "conversationTerms")
      )

    repo_root = get_optional(params, "repo_root") || context.repo_root
    backend = safe_module(get_optional(params, "backend"), context.backend)
    limit = parse_integer(get_optional(params, "limit"), fallback: 25)
    token_budget = get_optional(params, "token_budget")
    conversation_tokens = get_optional(params, "conversation_tokens")
    min_rank = parse_float(get_optional(params, "min_rank"), fallback: 0.0)

    include_clones =
      parse_boolean(get_optional(params, "include_clones"),
        fallback: Config.fetch(:include_clones)
      )

    opts = [
      backend: backend,
      repo_root: repo_root,
      limit: limit,
      min_rank: min_rank,
      include_clones: include_clones,
      active_file: active_file,
      mentioned_files: mentioned_files,
      edited_files: edited_files,
      conversation_terms: conversation_terms,
      graph_server: context.graph_server,
      symbol_graph_server: Map.get(context, :symbol_graph_server, SymbolGraphServer)
    ]

    opts =
      if token_budget != nil do
        Keyword.put(opts, :token_budget, parse_integer(token_budget, fallback: :auto))
      else
        opts
      end

    if conversation_tokens != nil do
      Keyword.put(opts, :conversation_tokens, parse_integer(conversation_tokens, fallback: nil))
    else
      opts
    end
  end

  defp query_opts(params, context) do
    repo_root = get_optional(params, "repo_root") || context.repo_root
    backend = safe_module(get_optional(params, "backend"), context.backend)
    [repo_root: repo_root, backend: backend, graph_server: context.graph_server]
  end

  defp parse_file_list(nil), do: []
  defp parse_file_list(value) when is_list(value), do: value
  defp parse_file_list(value) when is_binary(value), do: String.split(value, ",", trim: true)
  defp parse_file_list(_), do: []

  defp parse_integer(nil, fallback: fallback), do: fallback

  defp parse_integer(value, fallback: _fallback) when is_integer(value), do: value

  defp parse_integer(value, fallback: fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> fallback
    end
  end

  defp parse_integer(_value, fallback: fallback), do: fallback

  defp parse_float(nil, fallback: fallback), do: fallback
  defp parse_float(value, fallback: _fallback) when is_float(value), do: value
  defp parse_float(value, fallback: _fallback) when is_integer(value), do: value / 1.0

  defp parse_float(value, fallback: fallback) when is_binary(value) do
    case Float.parse(value) do
      {parsed, ""} -> parsed
      _ -> fallback
    end
  end

  defp parse_float(_value, fallback: fallback), do: fallback

  defp parse_boolean(nil, fallback: fallback), do: fallback
  defp parse_boolean(value, _fallback) when is_boolean(value), do: value

  defp parse_boolean(value, _fallback) when value in [1, "true", "TRUE", "1", "True"] do
    true
  end

  defp parse_boolean(value, _fallback) when value in [0, "false", "FALSE", "0", "False", false] do
    false
  end

  defp parse_boolean(_, fallback), do: fallback

  defp parse_arity(nil), do: nil
  defp parse_arity(value) when is_integer(value), do: value
  defp parse_arity(value) when is_binary(value), do: parse_integer(value, fallback: nil)
  defp parse_arity(_), do: nil

  defp get_required(map, key) do
    case get_optional(map, key) do
      nil -> raise ArgumentError, "missing required argument #{key}"
      value -> value
    end
  end

  defp get_optional(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp get_optional(_, _), do: nil

  defp safe_module(nil, default), do: default

  defp safe_module(value, default) do
    if is_atom(value) do
      value
    else
      Module.concat([value])
    end
  rescue
    _ -> default
  end

  defp response(nil, _result), do: %{}
  defp response(id, result), do: %{"jsonrpc" => @jsonrpc, "id" => id, "result" => result}

  defp error_payload(id, code, message, data) do
    %{
      "jsonrpc" => @jsonrpc,
      "id" => id,
      "error" => %{"code" => code, "message" => message, "data" => data}
    }
  end

  defp error_response(id, code, message, data) do
    error_payload(id, code, message, data)
  end

  defp encode_and_print({:ok, result}) do
    unless result == %{} do
      encoded = Jason.encode!(result)
      IO.puts(encoded)
    end

    :ok
  end

  defp encode_and_print({:error, payload}) do
    payload
    |> Jason.encode!()
    |> IO.puts()

    :ok
  end
end
