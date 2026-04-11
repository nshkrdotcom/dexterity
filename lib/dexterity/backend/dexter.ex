defmodule Dexterity.Backend.Dexter do
  @moduledoc """
  Dexter backend implementation backed by the Dexter CLI index database.
  """

  @behaviour Dexterity.Backend

  alias Dexterity.Config
  alias Exqlite.Basic

  @file_edges_sql """
  SELECT
    r.file_path AS source,
    d.file_path AS target,
    COUNT(*) AS ref_count
  FROM refs r
  JOIN definitions d
    ON r.module = d.module
   AND (
     (r.function != '' AND d.function = r.function) OR
       (r.function = '' AND d.function = '')
   )
  WHERE r.file_path != d.file_path
  GROUP BY r.file_path, d.file_path
  """

  @file_nodes_sql """
  SELECT DISTINCT file_path AS file FROM definitions
  UNION
  SELECT DISTINCT file_path AS file FROM refs
  """

  @exported_sql """
  SELECT module, function, arity, file_path, line
  FROM definitions
  WHERE file_path = ?1
    AND function != ''
    AND kind NOT IN ('callback', 'macrocallback')
  ORDER BY file_path ASC, line ASC
  """

  @find_definition_sql """
  SELECT module, function, arity, file_path, line
  FROM definitions
  """

  @find_references_sql """
  SELECT file_path, line
  FROM refs r
  """

  @spec db_path(String.t()) :: String.t()
  def db_path(repo_root), do: Path.join(repo_root, Config.fetch(:dexter_db))

  @impl Dexterity.Backend
  def list_file_edges(repo_root) do
    with {:ok, conn} <- open_db(repo_root),
         {:ok, _query, result, _conn} <- exec_query(conn, @file_edges_sql),
         :ok <- close(conn) do
      edges =
        for [source, target, ref_count] <- result.rows,
            (source != nil and target != nil and ref_count) && ref_count > 0 do
          {normalize_path(repo_root, source), normalize_path(repo_root, target),
           weight(ref_count)}
        end

      {:ok, edges}
    else
      {:error, reason} ->
        {:error, {:backend_query_failed, reason}}
    end
  end

  @impl Dexterity.Backend
  def list_file_nodes(repo_root) do
    with {:ok, conn} <- open_db(repo_root),
         {:ok, _query, result, _conn} <- exec_query(conn, @file_nodes_sql),
         :ok <- close(conn) do
      nodes =
        Enum.map(result.rows, fn [file] ->
          normalize_path(repo_root, file)
        end)

      {:ok, nodes}
    else
      {:error, reason} ->
        {:error, {:backend_query_failed, reason}}
    end
  end

  @impl Dexterity.Backend
  def list_exported_symbols(repo_root, file) do
    file = resolve_repo_path(repo_root, file)

    with {:ok, conn} <- open_db(repo_root),
         {:ok, _query, result, _conn} <- exec_query(conn, @exported_sql, [file]),
         :ok <- close(conn) do
      symbols = Enum.map(result.rows, &row_to_symbol(repo_root, &1))
      {:ok, symbols}
    else
      {:error, reason} ->
        {:error, {:backend_query_failed, reason}}
    end
  end

  @impl Dexterity.Backend
  def find_definition(repo_root, module_name, function_name, arity) do
    where =
      case {function_name, arity} do
        {nil, _} ->
          "WHERE module = ?1 AND function = '' AND kind IN ('module', 'defprotocol', 'defimpl')"

        {_, nil} ->
          "WHERE module = ?1 AND function = ?2"
          |> append_non_module_kinds()

        _ ->
          "WHERE module = ?1 AND function = ?2 AND arity = ?3"
          |> append_non_module_kinds()
      end

    params =
      case {function_name, arity} do
        {nil, _} -> [module_name]
        {_, nil} -> [module_name, function_name]
        {_, _} -> [module_name, function_name, arity]
      end

    sql = "#{@find_definition_sql} #{where} ORDER BY file_path ASC, line ASC"

    with {:ok, conn} <- open_db(repo_root),
         {:ok, _query, result, _conn} <- exec_query(conn, sql, params),
         :ok <- close(conn) do
      symbols = Enum.map(result.rows, &row_to_symbol(repo_root, &1))

      if symbols == [] do
        {:error, :not_found}
      else
        {:ok, symbols}
      end
    else
      {:error, reason} ->
        {:error, {:backend_query_failed, reason}}
    end
  end

  @impl Dexterity.Backend
  def find_references(repo_root, module_name, function_name, arity) do
    where =
      case {function_name, arity} do
        {nil, _} -> "WHERE r.module = ?1"
        {_, nil} -> "WHERE r.module = ?1 AND r.function = ?2"
        _ -> "WHERE r.module = ?1 AND r.function = ?2"
      end

    params =
      case {function_name, arity} do
        {nil, _} -> [module_name]
        {_, nil} -> [module_name, function_name]
        {_, _} -> [module_name, function_name]
      end

    sql = "#{@find_references_sql} #{where} ORDER BY file_path ASC, line ASC"

    with {:ok, conn} <- open_db(repo_root),
         {:ok, _query, result, _conn} <- exec_query(conn, sql, params),
         :ok <- close(conn) do
      refs =
        Enum.map(result.rows, fn [caller_file, line] ->
          %{file: normalize_path(repo_root, caller_file), line: line}
        end)

      {:ok, refs}
    else
      {:error, reason} ->
        {:error, {:backend_query_failed, reason}}
    end
  end

  @impl Dexterity.Backend
  def reindex_file(file, opts \\ []) do
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root()) |> Path.expand()
    args = ["reindex", file]

    run_command(args, repo_root)
  end

  @impl Dexterity.Backend
  def cold_index(repo_root, opts \\ []) do
    cwd = Keyword.get(opts, :repo_root, repo_root) |> Path.expand()
    run_command(["init", "."], cwd)
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

  defp exec_query(conn, sql) do
    exec_query(conn, sql, [])
  end

  defp exec_query(conn, sql, params) do
    case Basic.exec(conn, sql, params) do
      {:ok, _query, _result, _conn} = ok ->
        ok

      {:error, reason, _conn} ->
        {:error, normalize_error(reason)}
    end
  end

  defp normalize_error(%Exqlite.Error{} = error), do: error.message

  defp append_non_module_kinds(where_clause) do
    where_clause <> " AND kind NOT IN ('module', 'defprotocol', 'defimpl')"
  end

  defp row_to_symbol(repo_root, [module_name, function_name, arity, file, line]) do
    %{
      module: module_name,
      function: function_name,
      arity: arity,
      file: normalize_path(repo_root, file),
      line: line
    }
  end

  defp resolve_repo_path(repo_root, path) when is_binary(path) do
    if Path.type(path) == :absolute do
      path
    else
      Path.join(repo_root, path)
    end
  end

  defp normalize_path(repo_root, path) when is_binary(path) do
    expanded_root = Path.expand(repo_root)
    expanded_path = Path.expand(path)

    case String.trim_leading(expanded_path, expanded_root <> "/") do
      ^expanded_path -> path
      relative -> relative
    end
  end
end
