defmodule Dexterity.Store do
  @moduledoc """
  Manages the Dexterity SQLite database using Exqlite.
  """

  alias Exqlite.Basic

  @type db_conn :: Exqlite.Connection.t()

  @doc """
  Opens a connection to the SQLite database and initializes the schema.
  """
  @spec open(String.t()) :: {:ok, db_conn()} | {:error, term()}
  def open(path) do
    case Basic.open(path) do
      {:ok, conn} ->
        case init_schema(conn) do
          :ok ->
            {:ok, conn}

          {:error, reason} ->
            Basic.close(conn)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Closes the database connection.
  """
  @spec close(db_conn()) :: :ok | {:error, term()}
  def close(conn), do: Basic.close(conn)

  defp init_schema(conn) do
    schemas = [
      """
      CREATE TABLE IF NOT EXISTS cochanges (
        file_a    TEXT NOT NULL,
        file_b    TEXT NOT NULL,
        frequency INTEGER NOT NULL DEFAULT 0,
        weight    REAL NOT NULL DEFAULT 0.0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (file_a, file_b)
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS semantic_summaries (
        file       TEXT NOT NULL,
        module     TEXT NOT NULL,
        summary    TEXT NOT NULL,
        file_mtime INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (file, module)
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS pagerank_cache (
        file          TEXT PRIMARY KEY,
        score         REAL NOT NULL,
        computed_at   INTEGER NOT NULL
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS token_signatures (
        file      TEXT NOT NULL,
        module    TEXT NOT NULL,
        signature BLOB NOT NULL,
        PRIMARY KEY (file, module)
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS index_meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      """
    ]

    Enum.reduce_while(schemas, :ok, fn sql, acc ->
      case Basic.exec(conn, sql) do
        {:ok, _, _, _} -> {:cont, acc}
        {:error, reason, _} -> {:halt, {:error, reason}}
      end
    end)
  end
end
