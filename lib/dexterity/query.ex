defmodule Dexterity.Query do
  @moduledoc """
  Public semantic query façade.
  """

  alias Dexterity.Backend
  alias Dexterity.Config
  alias Dexterity.GraphServer
  alias Dexterity.Store
  alias Dexterity.StoreServer

  @type definition_filters :: [
          module: String.t(),
          function: String.t() | nil,
          arity: non_neg_integer() | nil
        ]

  @type blast_result :: %{source: String.t(), depth: non_neg_integer()}

  @spec find_definition(String.t(), String.t(), String.t() | nil, keyword()) ::
          {:ok, [Backend.symbol()]} | {:error, term()}
  def find_definition(module, function_name, arity, opts \\ []) do
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))
    backend.find_definition(repo_root, module, function_name, arity)
  end

  @spec find_references(String.t(), String.t() | nil, non_neg_integer() | nil, keyword()) ::
          {:ok, [Backend.reference_location()]} | {:error, term()}
  def find_references(module, function_name, arity, opts \\ []) do
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))
    backend.find_references(repo_root, module, function_name, arity)
  end

  @spec cochanges(String.t(), non_neg_integer(), keyword()) ::
          {:ok, [{String.t(), float()}]} | {:error, term()}
  def cochanges(file, limit \\ 10, opts \\ []) do
    with {:ok, conn} <- fetch_store_conn(opts),
         {:ok, rows} <- Store.list_cochanges(conn) do
      rows
      |> Enum.flat_map(fn {file_a, file_b, _frequency, weight} ->
        cond do
          file_a == file -> [{file_b, weight}]
          file_b == file -> [{file_a, weight}]
          true -> []
        end
      end)
      |> Enum.reject(fn {_neighbor, weight} -> weight <= 0 end)
      |> Enum.sort_by(fn {neighbor, weight} -> {-weight, neighbor} end)
      |> Enum.take(limit)
      |> then(&{:ok, &1})
    else
      {:error, _reason} ->
        {:error, :cochange_data_unavailable}
    end
  end

  @spec blast_radius(String.t(), keyword()) :: {:ok, [blast_result()]} | {:error, term()}
  def blast_radius(file, opts \\ []) do
    max_depth = Keyword.get(opts, :depth, 2)
    server = Keyword.get(opts, :graph_server, GraphServer)

    case GraphServer.get_adjacency(server) do
      adjacency when is_map(adjacency) ->
        {:ok, bfs_from(adjacency, file, max_depth)}

      _ ->
        {:error, :graph_unavailable}
    end
  end

  defp bfs_from(adjacency, source, max_depth) do
    initial_frontier = [{source, 0}]
    visited = %{source => 0}

    {visited, _frontier} =
      Enum.reduce_while(1..max_depth, {visited, initial_frontier}, fn _depth, {seen, frontier} ->
        {next_level, next_frontier} =
          Enum.reduce(frontier, {MapSet.new(), []}, fn {node, depth}, {next_nodes, next_acc} ->
            Map.get(adjacency, node, %{})
            |> Map.keys()
            |> Enum.reduce({next_nodes, next_acc}, fn neighbor, {next_nodes, next_acc} ->
              if Map.has_key?(seen, neighbor) do
                {next_nodes, next_acc}
              else
                {MapSet.put(next_nodes, neighbor), [{neighbor, depth + 1} | next_acc]}
              end
            end)
          end)

        if MapSet.size(next_level) == 0 do
          {:halt, {seen, []}}
        else
          updated =
            Enum.reduce(next_frontier, seen, fn {node, depth}, acc ->
              Map.put(acc, node, depth)
            end)

          {:cont, {updated, Enum.uniq(next_frontier)}}
        end
      end)

    Enum.map(visited, fn {file, depth} -> %{source: file, depth: depth} end)
    |> Enum.sort_by(fn item -> {item.depth, item.source} end)
  end

  defp fetch_store_conn(opts) do
    case Keyword.get(opts, :store_conn) do
      nil ->
        store_server = Keyword.get(opts, :store_server, StoreServer)

        case Process.whereis(store_server) do
          nil -> {:error, :store_unavailable}
          _pid -> {:ok, StoreServer.conn(store_server)}
        end

      conn ->
        {:ok, conn}
    end
  rescue
    _ -> {:error, :store_unavailable}
  end
end
