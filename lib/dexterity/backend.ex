defmodule Dexterity.Backend do
  @moduledoc """
  Behaviour for extracting semantic information from an index.
  """

  @type file_edge :: {caller_file :: String.t(), target_file :: String.t(), weight :: float()}
  @type symbol :: %{
          module: String.t(),
          function: String.t(),
          arity: integer(),
          file: String.t(),
          line: integer()
        }

  @callback list_file_edges(repo_root :: String.t()) :: [file_edge()]
  @callback list_exported_symbols(repo_root :: String.t(), file :: String.t()) :: [symbol()]
  @callback reindex_file(file :: String.t()) :: :ok | {:error, term()}
  @callback cold_index(repo_root :: String.t()) :: :ok | {:error, term()}
  @callback index_status(repo_root :: String.t()) :: :ready | :stale | :missing
end
