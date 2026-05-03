defmodule Dexterity.Intelligence do
  @moduledoc false

  alias Dexterity.AnalysisSupport
  alias Dexterity.Config
  alias Dexterity.GraphServer

  @type ranked_symbol :: %{
          module: String.t(),
          function: String.t(),
          arity: non_neg_integer(),
          file: String.t(),
          line: non_neg_integer(),
          rank: float()
        }

  @spec find_symbols(String.t(), keyword()) :: {:ok, [ranked_symbol()]} | {:error, term()}
  def find_symbols(query, opts \\ [])

  def find_symbols(query, opts) when is_binary(query) do
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    limit = Keyword.get(opts, :limit, 10)
    baseline = AnalysisSupport.baseline_rank(Keyword.get(opts, :graph_server, GraphServer))
    normalized_query = String.downcase(String.trim(query))

    with {:ok, symbols} <- AnalysisSupport.collect_symbols(backend, repo_root) do
      symbols
      |> Enum.filter(&(match_score(&1, normalized_query) > 0))
      |> Enum.map(fn symbol ->
        Map.put(symbol, :rank, Map.get(baseline, symbol.file, 0.0))
      end)
      |> Enum.sort_by(fn symbol ->
        rank = Map.get(symbol, :rank, 0.0) || 0.0
        {-match_score(symbol, normalized_query), -rank, symbol.file, symbol.line}
      end)
      |> Enum.take(limit)
      |> then(&{:ok, &1})
    end
  end

  def find_symbols(_query, _opts), do: {:error, :invalid_query}

  @spec match_files(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def match_files(pattern, opts \\ [])

  def match_files(pattern, opts) when is_binary(pattern) do
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    limit = Keyword.get(opts, :limit, 20)
    baseline = AnalysisSupport.baseline_rank(Keyword.get(opts, :graph_server, GraphServer))
    like_tokens = like_tokens(pattern)

    with {:ok, files} <- backend.list_file_nodes(repo_root) do
      files
      |> Enum.filter(
        &(AnalysisSupport.project_file?(repo_root, &1) and like_match?(like_tokens, &1))
      )
      |> Enum.uniq()
      |> Enum.sort_by(fn file -> {-Map.get(baseline, file, 0.0), file} end)
      |> Enum.take(limit)
      |> then(&{:ok, &1})
    end
  end

  def match_files(_pattern, _opts), do: {:error, :invalid_pattern}

  @spec blast_radius_count(String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def blast_radius_count(file, opts \\ []) when is_binary(file) do
    graph_server = Keyword.get(opts, :graph_server, GraphServer)

    case GraphServer.get_adjacency(graph_server) do
      adjacency when is_map(adjacency) ->
        count =
          Enum.count(adjacency, fn {_source, targets} ->
            is_map(targets) and Map.has_key?(targets, file)
          end)

        {:ok, count}

      _ ->
        {:error, :graph_unavailable}
    end
  rescue
    _ -> {:error, :graph_unavailable}
  end

  defp match_score(symbol, query) do
    exact_score = exact_match_score(symbol, query)
    contains_score = contains_match_score(symbol, query)
    file_score = file_match_score(symbol, query)

    Enum.find([exact_score, contains_score, file_score], 0, &(&1 > 0))
  end

  defp exact_match_score(symbol, query) do
    function = String.downcase(symbol.function || "")
    module_name = String.downcase(symbol.module || "")
    module_leaf = module_leaf(module_name)

    cond do
      query == "" -> 0
      function == query -> 5
      module_name == query or module_leaf == query -> 4
      true -> 0
    end
  end

  defp contains_match_score(symbol, query) do
    file = String.downcase(symbol.file)
    function = String.downcase(symbol.function || "")
    module_name = String.downcase(symbol.module || "")
    module_leaf = module_leaf(module_name)

    cond do
      query == "" -> 0
      String.contains?(function, query) -> 3
      String.contains?(module_name, query) or String.contains?(module_leaf, query) -> 2
      String.contains?(file, query) -> 1
      true -> 0
    end
  end

  defp file_match_score(symbol, query) do
    file = String.downcase(symbol.file)

    if query != "" and String.contains?(file, query) do
      1
    else
      0
    end
  end

  defp module_leaf(module_name) do
    module_name
    |> String.split(".")
    |> List.last()
    |> to_string()
  end

  defp like_tokens(pattern) do
    pattern
    |> String.downcase()
    |> String.graphemes()
    |> build_like_tokens([], false)
    |> Enum.reverse()
  end

  defp build_like_tokens([], acc, false), do: acc
  defp build_like_tokens([], acc, true), do: [{:literal, "\\"} | acc]

  defp build_like_tokens([char | rest], acc, true) do
    build_like_tokens(rest, [{:literal, char} | acc], false)
  end

  defp build_like_tokens(["\\" | rest], acc, false), do: build_like_tokens(rest, acc, true)

  defp build_like_tokens(["%" | rest], acc, false),
    do: build_like_tokens(rest, [:many | acc], false)

  defp build_like_tokens(["_" | rest], acc, false),
    do: build_like_tokens(rest, [:one | acc], false)

  defp build_like_tokens([char | rest], acc, false) do
    build_like_tokens(rest, [{:literal, char} | acc], false)
  end

  defp like_match?(tokens, value) do
    do_like_match?(tokens, value |> String.downcase() |> String.graphemes())
  end

  defp do_like_match?([], []), do: true
  defp do_like_match?([], _chars), do: false
  defp do_like_match?([:one | rest], [_char | chars]), do: do_like_match?(rest, chars)
  defp do_like_match?([:one | _rest], []), do: false

  defp do_like_match?([:many | rest] = tokens, chars) do
    do_like_match?(rest, chars) or
      case chars do
        [_char | remaining] -> do_like_match?(tokens, remaining)
        [] -> false
      end
  end

  defp do_like_match?([{:literal, char} | rest], [char | chars]), do: do_like_match?(rest, chars)
  defp do_like_match?([{:literal, _char} | _rest], _chars), do: false
end
