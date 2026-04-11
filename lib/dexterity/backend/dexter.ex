defmodule Dexterity.Backend.Dexter do
  @moduledoc """
  Implementation of Dexterity.Backend that uses the `dexter` CLI and `.dexter.db`.
  """
  @behaviour Dexterity.Backend

  alias Exqlite.Basic

  @impl Dexterity.Backend
  def list_file_edges(repo_root) do
    db_path = Path.join(repo_root, ".dexter.db")

    with {:ok, conn} <- Basic.open(db_path),
         {:ok, _query, result, _conn} <-
           Basic.exec(conn, """
           SELECT
             r.caller_file AS source,
             d.file         AS target,
             COUNT(*)       AS ref_count
           FROM "references" r
           JOIN definitions d
             ON  r.target_module   = d.module
             AND r.target_function = d.function
             AND r.target_arity    = d.arity
           WHERE r.caller_file != d.file
           GROUP BY r.caller_file, d.file
           """) do
      Basic.close(conn)

      Enum.map(result.rows, fn [source, target, ref_count] ->
        weight = :math.sqrt(ref_count) * 3.0
        {source, target, weight}
      end)
    else
      _ -> []
    end
  end

  @impl Dexterity.Backend
  def list_exported_symbols(repo_root, file) do
    db_path = Path.join(repo_root, ".dexter.db")

    with {:ok, conn} <- Basic.open(db_path),
         {:ok, _query, result, _conn} <-
           Basic.exec(
             conn,
             "SELECT module, function, arity, file, line FROM definitions WHERE file = ?1",
             [file]
           ) do
      Basic.close(conn)

      Enum.map(result.rows, fn [module, function, arity, f, line] ->
        %{
          module: module,
          function: function,
          arity: arity,
          file: f,
          line: line
        }
      end)
    else
      _ -> []
    end
  end

  @impl Dexterity.Backend
  def reindex_file(file) do
    case System.cmd("dexter", ["reindex", file]) do
      {_, 0} -> :ok
      {err, _} -> {:error, err}
    end
  rescue
    e -> {:error, e}
  end

  @impl Dexterity.Backend
  def cold_index(repo_root) do
    case System.cmd("dexter", ["index"], cd: repo_root) do
      {_, 0} -> :ok
      {err, _} -> {:error, err}
    end
  rescue
    e -> {:error, e}
  end

  @impl Dexterity.Backend
  def index_status(repo_root) do
    db_path = Path.join(repo_root, ".dexter.db")

    if File.exists?(db_path) do
      :ready
    else
      :missing
    end
  end
end
