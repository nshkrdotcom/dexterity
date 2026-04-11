defmodule Dexterity.Backend.Dexter do
  @moduledoc """
  Dexter backend implementation backed by the Dexter CLI index database.
  """

  @behaviour Dexterity.Backend

  alias Dexterity.Config
  alias Exqlite.Basic

  @file_edges_sql """
  SELECT
    r.caller_file AS source,
    d.file         AS target,
    COUNT(*)       AS ref_count
  FROM "references" r
  JOIN definitions d
    ON r.target_module = d.module
   AND r.target_function = d.function
   AND r.target_arity = d.arity
  WHERE r.caller_file != d.file
  GROUP BY r.caller_file, d.file
  """

  @file_nodes_sql """
  SELECT DISTINCT file FROM definitions
  UNION
  SELECT DISTINCT caller_file AS file FROM "references"
  """

  @exported_sql """
  SELECT module, function, arity, file, line
  FROM definitions
  WHERE file = ?1
  ORDER BY file ASC, line ASC
  """

  @find_definition_sql """
  SELECT module, function, arity, file, line
  FROM definitions
  """

  @find_references_sql """
  SELECT caller_file, line
  FROM "references" r
  """

  @spec db_path(String.t()) :: String.t()
  def db_path(repo_root), do: Path.join(repo_root, Config.fetch(:dexter_db))

  @impl Dexterity.Backend
  def list_file_edges(repo_root) do
    with {:ok, conn} <- open_db(repo_root),
         {:ok, _query, result, _conn} <- Basic.exec(conn, @file_edges_sql),
         :ok <- close(conn) do
      edges =
        for [source, target, ref_count] <- result.rows,
            source != nil and target != nil and ref_count && ref_count > 0 do
          {source, target, weight(ref_count)}
        end

      {:ok, edges}
    else
      {:error, {:exqlite_error, %Exqlite.Error{} = error}} ->
        {:error, {:backend_query_failed, error.message}}

      {:error, reason} ->
        {:error, {:backend_query_failed, reason}}
    end
  end

  @impl Dexterity.Backend
  def list_file_nodes(repo_root) do
    with {:ok, conn} <- open_db(repo_root),
         {:ok, _query, result, _conn} <- Basic.exec(conn, @file_nodes_sql),
         :ok <- close(conn) do
      nodes =
        Enum.map(result.rows, fn [file] ->
          file
        end)

      {:ok, nodes}
    else
      {:error, {:exqlite_error, %Exqlite.Error{} = error}} ->
        {:error, {:backend_query_failed, error.message}}

      {:error, reason} ->
        {:error, {:backend_query_failed, reason}}
    end
  end

  @impl Dexterity.Backend
  def list_exported_symbols(repo_root, file) do
    with {:ok, conn} <- open_db(repo_root),
         {:ok, _query, result, _conn} <- Basic.exec(conn, @exported_sql, [file]),
         :ok <- close(conn) do
      symbols = Enum.map(result.rows, &row_to_symbol/1)
      {:ok, symbols}
    else
      {:error, {:exqlite_error, %Exqlite.Error{} = error}} ->
        {:error, {:backend_query_failed, error.message}}

      {:error, reason} ->
        {:error, {:backend_query_failed, reason}}
    end
  end

  @impl Dexterity.Backend
  def find_definition(repo_root, module_name, function_name, arity) do
    where =
      case {function_name, arity} do
        {nil, _} -> "WHERE module = ?1"
        {_, nil} -> "WHERE module = ?1 AND function = ?2"
        _ -> "WHERE module = ?1 AND function = ?2 AND arity = ?3"
      end

    params =
      case {function_name, arity} do
        {nil, _} -> [module_name]
        {_, nil} -> [module_name, function_name]
        {_, _} -> [module_name, function_name, arity]
      end

    sql = "#{@find_definition_sql} #{where} ORDER BY file ASC, line ASC"

    with {:ok, conn} <- open_db(repo_root),
         {:ok, _query, result, _conn} <- Basic.exec(conn, sql, params),
         :ok <- close(conn) do
      symbols = Enum.map(result.rows, &row_to_symbol/1)

      if symbols == [] do
        {:error, :not_found}
      else
        {:ok, symbols}
      end
    else
      {:error, {:exqlite_error, %Exqlite.Error{} = error}} ->
        {:error, {:backend_query_failed, error.message}}

      {:error, reason} ->
        {:error, {:backend_query_failed, reason}}
    end
  end

  @impl Dexterity.Backend
  def find_references(repo_root, module_name, function_name, arity) do
    where =
      case {function_name, arity} do
        {nil, _} -> "WHERE r.target_module = ?1"
        {_, nil} -> "WHERE r.target_module = ?1 AND r.target_function = ?2"
        _ -> "WHERE r.target_module = ?1 AND r.target_function = ?2 AND r.target_arity = ?3"
      end

    params =
      case {function_name, arity} do
        {nil, _} -> [module_name]
        {_, nil} -> [module_name, function_name]
        {_, _} -> [module_name, function_name, arity]
      end

    sql = "#{@find_references_sql} #{where} ORDER BY caller_file ASC, line ASC"

    with {:ok, conn} <- open_db(repo_root),
         {:ok, _query, result, _conn} <- Basic.exec(conn, sql, params),
         :ok <- close(conn) do
      refs =
        Enum.map(result.rows, fn [caller_file, line] ->
          %{file: caller_file, line: line}
        end)

      {:ok, refs}
    else
      {:error, {:exqlite_error, %Exqlite.Error{} = error}} ->
        {:error, {:backend_query_failed, error.message}}

      {:error, reason} ->
        {:error, {:backend_query_failed, reason}}
    end
  end

  @impl Dexterity.Backend
  def reindex_file(file, opts \\ []) do
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    args = ["reindex", file]

    run_command(args, repo_root)
  end

  @impl Dexterity.Backend
  def cold_index(repo_root, opts \\ []) do
    cwd = Keyword.get(opts, :repo_root, repo_root)
    run_command(["index"], cwd)
  end

  @impl Dexterity.Backend
  def index_status(repo_root) do
    path = db_path(repo_root)

    if File.exists?(path) do
      {:ok, :ready}
    else
      {:ok, :missing}
    end
  end

  @impl Dexterity.Backend
  def healthy?(repo_root) do
    case System.find_executable(Config.fetch(:dexter_bin)) do
      nil ->
        {:error, :backend_missing_binary}

      _ ->
        repo_root = repo_root || Config.repo_root()
        with {:ok, status} when status in [:ready, :missing, :stale] <- index_status(repo_root) do
          {:ok, status == :ready}
        end
    end
  end

  defp weight(ref_count) do
    :math.sqrt(ref_count) * 3.0
  end

  defp open_db(repo_root) do
    path = db_path(repo_root)

    if File.exists?(path) do
      Basic.open(path)
    else
      {:error, {:backend_missing_db, path}}
    end
  end

  defp close(conn) do
    case Basic.close(conn) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_command(args, repo_root) do
    case System.cmd(Config.fetch(:dexter_bin), args, cd: repo_root, stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, _exit} ->
        {:error, {:command_failed, output}}
    end
    rescue
      error ->
        {:error, {:command_failed, Exception.message(error)}}
  end

  defp row_to_symbol([module_name, function_name, arity, file, line]) do
    %{
      module: module_name,
      function: function_name,
      arity: arity,
      file: file,
      line: line
    }
  end
end
