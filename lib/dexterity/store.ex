defmodule Dexterity.Store do
  @moduledoc """
  SQLite persistence for Dexterity metadata.
  """

  alias Exqlite.Basic

  @schema_version 3
  @type db_conn :: Exqlite.Connection.t()

  @doc """
  Opens a Dexterity metadata connection and ensures schema exists.
  """
  @spec open(String.t()) :: {:ok, db_conn()} | {:error, term()}
  def open(path) do
    dir = Path.dirname(path)

    with :ok <- File.mkdir_p(dir),
         {:ok, conn} <- Basic.open(path),
         :ok <- init_schema(conn) do
      {:ok, conn}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Closes an open database connection.
  """
  @spec close(db_conn()) :: :ok | {:error, term()}
  def close(conn), do: Basic.close(conn)

  @doc """
  Returns all co-change edges with metadata.
  """
  @spec upsert_cochange(db_conn(), String.t(), String.t(), integer(), float(), integer()) ::
          :ok | {:error, term()}
  def upsert_cochange(conn, file_a, file_b, frequency, weight, now) do
    normalized = normalize_pair(file_a, file_b)

    sql = """
    INSERT INTO cochanges (file_a, file_b, frequency, weight, updated_at)
    VALUES (?1, ?2, ?3, ?4, ?5)
    ON CONFLICT(file_a, file_b) DO UPDATE SET
      frequency = excluded.frequency,
      weight = excluded.weight,
      updated_at = excluded.updated_at
    """

    exec!(conn, sql, [normalized.a, normalized.b, frequency, weight, now])
  end

  @doc """
  Lists co-change edges.
  """
  @spec list_cochanges(db_conn()) ::
          {:ok, [{String.t(), String.t(), integer(), float()}]} | {:error, term()}
  def list_cochanges(conn) do
    with {:ok, result} <-
           query_rows(conn, "SELECT file_a, file_b, frequency, weight FROM cochanges") do
      {:ok,
       Enum.map(result, fn [a, b, frequency, weight] ->
         {a, b, frequency, weight}
       end)}
    end
  end

  @doc """
  Caches semantic summary rows for modules.
  """
  @spec upsert_summary(
          db_conn(),
          String.t(),
          String.t(),
          String.t(),
          integer(),
          binary(),
          integer()
        ) ::
          :ok | {:error, term()}
  def upsert_summary(conn, file, module_name, summary, file_mtime, signature, now) do
    sql = """
    INSERT INTO semantic_summaries (file, module, summary, file_mtime, signature, created_at)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6)
    ON CONFLICT(file, module) DO UPDATE SET
      summary = excluded.summary,
      file_mtime = excluded.file_mtime,
      signature = excluded.signature,
      created_at = excluded.created_at
    """

    exec!(conn, sql, [file, module_name, summary, file_mtime, signature, now])
  end

  @doc """
  Reads cached summary for file/module.
  """
  @spec get_summary(db_conn(), String.t(), String.t()) ::
          {:ok, nil | {String.t(), integer(), binary()}} | {:error, term()}
  def get_summary(conn, file, module_name) do
    with {:ok, result} <-
           query_rows(
             conn,
             "SELECT summary, file_mtime, signature FROM semantic_summaries WHERE file = ?1 AND module = ?2",
             [file, module_name]
           ) do
      case result do
        [] ->
          {:ok, nil}

        [[summary, mtime, signature]] ->
          {:ok, {summary, mtime, signature}}
      end
    end
  end

  @doc """
  Caches token signatures used for clone detection.
  """
  @spec upsert_token_signature(db_conn(), String.t(), String.t(), binary()) ::
          :ok | {:error, term()}
  def upsert_token_signature(conn, file, module_name, signature) do
    sql = """
    INSERT INTO token_signatures (file, module, signature)
    VALUES (?1, ?2, ?3)
    ON CONFLICT(file, module) DO UPDATE SET
      signature = excluded.signature
    """

    exec!(conn, sql, [file, module_name, signature])
  end

  @doc """
  Reads a cached token signature for a file/module pair.
  """
  @spec get_token_signature(db_conn(), String.t(), String.t()) ::
          {:ok, binary() | nil} | {:error, term()}
  def get_token_signature(conn, file, module_name) do
    with {:ok, result} <-
           query_rows(
             conn,
             "SELECT signature FROM token_signatures WHERE file = ?1 AND module = ?2",
             [file, module_name]
           ) do
      case result do
        [] -> {:ok, nil}
        [[signature]] -> {:ok, signature}
      end
    end
  end

  @doc """
  Writes computed pagerank cache values.
  """
  @spec upsert_pagerank_cache(db_conn(), %{String.t() => float()}, integer()) ::
          :ok | {:error, term()}
  def upsert_pagerank_cache(conn, scores, computed_at) do
    with {:ok, _conn} <- upsert_many(conn, scores, computed_at) do
      :ok
    end
  end

  @doc """
  Returns cached pagerank map.
  """
  @spec list_pagerank_cache(db_conn()) :: {:ok, %{String.t() => float()}} | {:error, term()}
  def list_pagerank_cache(conn) do
    with {:ok, result} <- query_rows(conn, "SELECT file, score FROM pagerank_cache") do
      {:ok, Map.new(result, fn [file, score] -> {file, score} end)}
    end
  end

  @doc """
  Upserts generic metadata string value.
  """
  @spec set_meta(db_conn(), String.t(), String.t()) :: :ok | {:error, term()}
  def set_meta(conn, key, value) do
    exec!(
      conn,
      "INSERT INTO index_meta (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
      [key, value]
    )
  end

  @doc """
  Returns metadata value by key.
  """
  @spec get_meta(db_conn(), String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def get_meta(conn, key) do
    with {:ok, result} <- query_rows(conn, "SELECT value FROM index_meta WHERE key = ?1", [key]) do
      case result do
        [] -> {:ok, nil}
        [[value]] -> {:ok, value}
      end
    end
  end

  @doc """
  Persists runtime evidence for an exported symbol.
  """
  @spec upsert_runtime_observation(
          db_conn(),
          String.t(),
          String.t(),
          String.t(),
          non_neg_integer(),
          String.t(),
          non_neg_integer(),
          integer()
        ) :: :ok | {:error, term()}
  def upsert_runtime_observation(
        conn,
        file,
        module_name,
        function_name,
        arity,
        source,
        call_count,
        observed_at
      ) do
    sql = """
    INSERT INTO runtime_observations (file, module, function, arity, source, call_count, observed_at)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
    ON CONFLICT(file, module, function, arity, source) DO UPDATE SET
      call_count = excluded.call_count,
      observed_at = excluded.observed_at
    """

    exec!(conn, sql, [file, module_name, function_name, arity, source, call_count, observed_at])
  end

  @doc """
  Lists persisted runtime evidence rows.
  """
  @spec list_runtime_observations(db_conn()) :: {:ok, [map()]} | {:error, term()}
  def list_runtime_observations(conn) do
    with {:ok, rows} <-
           query_rows(
             conn,
             """
             SELECT file, module, function, arity, source, call_count, observed_at
             FROM runtime_observations
             ORDER BY module, function, arity, source
             """
           ) do
      {:ok,
       Enum.map(rows, fn [
                           file,
                           module_name,
                           function_name,
                           arity,
                           source,
                           call_count,
                           observed_at
                         ] ->
         %{
           file: file,
           module: module_name,
           function: function_name,
           arity: arity,
           source: source,
           call_count: call_count,
           observed_at: observed_at
         }
       end)}
    end
  end

  @doc """
  Truncates all Dexterity tables, except indexes.
  """
  @spec clear_all(db_conn()) :: :ok | {:error, term()}
  def clear_all(conn) do
    statements = [
      "DELETE FROM cochanges;",
      "DELETE FROM semantic_summaries;",
      "DELETE FROM pagerank_cache;",
      "DELETE FROM token_signatures;",
      "DELETE FROM runtime_observations;",
      "DELETE FROM index_meta;"
    ]

    Enum.reduce_while(statements, :ok, fn sql, acc ->
      case acc do
        :ok ->
          case exec(conn, sql, []) do
            {:ok, _query, _result, _conn} ->
              {:cont, :ok}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        {:error, _reason} ->
          {:halt, acc}
      end
    end)
  end

  @doc """
  Ensures default schema exists for all managed tables.
  """
  @spec init_schema(db_conn()) :: :ok | {:error, term()}
  def init_schema(conn) do
    tables = [
      """
      CREATE TABLE IF NOT EXISTS schema_version (
        version INTEGER PRIMARY KEY
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS cochanges (
        file_a TEXT NOT NULL,
        file_b TEXT NOT NULL,
        frequency INTEGER NOT NULL DEFAULT 0,
        weight REAL NOT NULL DEFAULT 0.0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (file_a, file_b)
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS semantic_summaries (
        file TEXT NOT NULL,
        module TEXT NOT NULL,
        summary TEXT NOT NULL,
        file_mtime INTEGER NOT NULL,
        signature BLOB NOT NULL DEFAULT x'',
        created_at INTEGER NOT NULL,
        PRIMARY KEY (file, module)
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS pagerank_cache (
        file TEXT PRIMARY KEY,
        score REAL NOT NULL,
        computed_at INTEGER NOT NULL
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS token_signatures (
        file TEXT NOT NULL,
        module TEXT NOT NULL,
        signature BLOB NOT NULL,
        PRIMARY KEY (file, module)
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS index_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS runtime_observations (
        file TEXT NOT NULL,
        module TEXT NOT NULL,
        function TEXT NOT NULL,
        arity INTEGER NOT NULL,
        source TEXT NOT NULL,
        call_count INTEGER NOT NULL DEFAULT 0,
        observed_at INTEGER NOT NULL,
        PRIMARY KEY (file, module, function, arity, source)
      );
      """
    ]

    case exec_sql_list(conn, tables) do
      :ok ->
        with :ok <- ensure_summary_signature_column(conn) do
          set_schema_version(conn, @schema_version)
        end

      error ->
        error
    end
  end

  defp set_schema_version(conn, version) do
    exec!(conn, "INSERT OR REPLACE INTO schema_version (version) VALUES (?1)", [version])
  end

  defp ensure_summary_signature_column(conn) do
    with {:ok, rows} <- query_rows(conn, "PRAGMA table_info(semantic_summaries)") do
      column_names = Enum.map(rows, fn [_cid, name | _rest] -> name end)

      if "signature" in column_names do
        :ok
      else
        exec!(
          conn,
          "ALTER TABLE semantic_summaries ADD COLUMN signature BLOB NOT NULL DEFAULT x''",
          []
        )
      end
    end
  end

  defp normalize_pair(a, b) when a < b, do: %{a: a, b: b}
  defp normalize_pair(a, b), do: %{a: b, b: a}

  defp upsert_many(conn, scores, computed_at) do
    Enum.reduce_while(scores, {:ok, conn}, fn {file, score}, {:ok, _conn} ->
      case exec!(
             conn,
             "INSERT INTO pagerank_cache (file, score, computed_at) VALUES (?1, ?2, ?3) ON CONFLICT(file) DO UPDATE SET score = excluded.score, computed_at = excluded.computed_at",
             [file, score, computed_at]
           ) do
        :ok -> {:cont, {:ok, conn}}
        error -> {:halt, error}
      end
    end)
  end

  defp exec_sql_list(conn, queries) do
    Enum.reduce_while(queries, :ok, fn sql, acc ->
      case acc do
        :ok ->
          case exec(conn, sql, []) do
            {:ok, _query, _result, _conn} ->
              {:cont, :ok}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        _ ->
          {:halt, acc}
      end
    end)
  end

  defp query_rows(conn, sql, params \\ []) do
    with {:ok, _query, result, _conn} <- exec(conn, sql, params) do
      {:ok, result.rows}
    end
  end

  defp exec(conn, sql, params) do
    case Basic.exec(conn, sql, params) do
      {:ok, query, result, conn_state} ->
        {:ok, query, result, conn_state}

      {:error, reason, _conn} ->
        {:error, normalize_error(reason)}
    end
  end

  defp normalize_error(%Exqlite.Error{} = error), do: error.message

  defp exec!(conn, sql, params) do
    case exec(conn, sql, params) do
      {:ok, _query, _result, _conn} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
