defmodule Dexterity.Backend do
  @moduledoc """
  Behaviour for accessing project semantic indices.
  """

  @type file_edge :: {caller_file :: String.t(), target_file :: String.t(), weight :: float()}
  @type symbol :: %{
          module: String.t(),
          function: String.t(),
          arity: integer(),
          file: String.t(),
          line: integer()
        }
  @type symbol_node :: %{
          required(:module) => String.t(),
          required(:function) => String.t(),
          required(:arity) => integer(),
          required(:file) => String.t(),
          required(:line) => integer(),
          optional(:end_line) => integer(),
          optional(:signature) => String.t(),
          optional(:visibility) => :public | :private,
          optional(:kind) => String.t()
        }
  @type symbol_ref :: %{
          module: String.t(),
          function: String.t(),
          arity: integer(),
          file: String.t(),
          line: integer()
        }
  @type symbol_edge :: %{
          source: symbol_ref(),
          target: symbol_ref(),
          weight: float()
        }
  @type reference_location :: %{file: String.t(), line: integer() | nil}
  @type index_status :: :ready | :stale | :missing | :error

  @type backend_error ::
          {:error, reason :: term()}

  @callback list_file_edges(repo_root :: String.t()) ::
              {:ok, [file_edge()]} | backend_error()
  @callback list_file_nodes(repo_root :: String.t()) ::
              {:ok, [String.t()]} | backend_error()
  @callback list_exported_symbols(repo_root :: String.t(), file :: String.t()) ::
              {:ok, [symbol()]} | backend_error()
  @callback list_symbol_nodes(repo_root :: String.t()) ::
              {:ok, [symbol_node()]} | backend_error()
  @callback list_symbol_edges(repo_root :: String.t()) ::
              {:ok, [symbol_edge()]} | backend_error()
  @callback find_definition(
              repo_root :: String.t(),
              module :: String.t(),
              function_name :: String.t() | nil,
              arity :: non_neg_integer() | nil
            ) :: {:ok, [symbol()]} | {:error, :not_found} | backend_error()
  @callback find_references(
              repo_root :: String.t(),
              module :: String.t(),
              function_name :: String.t() | nil,
              arity :: non_neg_integer() | nil
            ) :: {:ok, [reference_location()]} | backend_error()
  @callback reindex_file(file :: String.t(), opts :: keyword()) :: :ok | backend_error()
  @callback cold_index(repo_root :: String.t(), opts :: keyword()) :: :ok | backend_error()
  @callback index_status(repo_root :: String.t()) :: {:ok, index_status()} | backend_error()
  @callback healthy?(repo_root :: String.t()) :: {:ok, true | false} | backend_error()

  @optional_callbacks list_symbol_nodes: 1, list_symbol_edges: 1
end
