defmodule Dexterity.Graph do
  @moduledoc """
  Graph query entry point for ranking and adjacency.
  """

  alias Dexterity.GraphServer

  @spec get_adjacency(keyword()) :: %{String.t() => %{String.t() => float()}} | {:error, term()}
  def get_adjacency(opts \\ []) do
    server = Keyword.get(opts, :server, GraphServer)
    {:ok, GraphServer.get_adjacency(server)}
  rescue
    _ -> {:error, :graph_unavailable}
  end

  @spec pagerank([String.t()], keyword()) :: {:ok, [{String.t(), float()}]} | {:error, term()}
  def pagerank(context_files, opts \\ []) do
    server = Keyword.get(opts, :server, GraphServer)

    case GraphServer.get_repo_map(server, context_files, opts) do
      {:ok, ranks} -> {:ok, ranks}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec baseline(keyword()) :: {:ok, %{String.t() => float()}} | {:error, term()}
  def baseline(opts \\ []) do
    server = Keyword.get(opts, :server, GraphServer)
    {:ok, GraphServer.get_baseline_rank(server)}
  rescue
    _ -> {:error, :graph_unavailable}
  end
end
