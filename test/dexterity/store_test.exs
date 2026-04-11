defmodule Dexterity.StoreTest do
  use ExUnit.Case

  alias Dexterity.Store

  setup do
    path = Path.join(System.tmp_dir!(), "dexterity-store-test-#{:erlang.unique_integer([:positive])}.db")
    File.rm(path)

    on_exit(fn -> File.rm(path) end)

    %{path: path}
  end

  test "opens database and initializes schema", %{path: path} do
    assert {:ok, conn} = Store.open(path)
    assert File.exists?(path)

    {:ok, _query, result, _conn} = Exqlite.Basic.exec(
      conn,
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
    )

    rows = result.rows |> List.flatten()
    assert "cochanges" in rows
    assert "semantic_summaries" in rows
    assert "pagerank_cache" in rows
    assert "token_signatures" in rows
    assert "index_meta" in rows

    assert :ok = Store.close(conn)
  end

  test "cochanges are upserted and listed", %{path: path} do
    {:ok, conn} = Store.open(path)

    assert :ok = Store.upsert_cochange(conn, "lib/a.ex", "lib/b.ex", 3, 2.5, 1_000)
    assert :ok = Store.upsert_cochange(conn, "lib/b.ex", "lib/a.ex", 4, 3.1, 1_000)

    assert {:ok, cochanges} = Store.list_cochanges(conn)
    assert [{"lib/a.ex", "lib/b.ex", 4, 3.1}] = cochanges

    assert :ok = Store.close(conn)
  end

  test "semantic summaries are inserted and read", %{path: path} do
    {:ok, conn} = Store.open(path)

    signature = <<1, 2, 3>>

    assert :ok =
             Store.upsert_summary(
               conn,
               "lib/a.ex",
               "MyModule",
               "Summary",
               1_700_000,
               signature,
               1_700_001
             )

    assert {:ok, {"Summary", 1_700_000, ^signature}} = Store.get_summary(conn, "lib/a.ex", "MyModule")

    assert :ok = Store.close(conn)
  end

  test "pagerank cache read/write works", %{path: path} do
    {:ok, conn} = Store.open(path)

    assert :ok = Store.upsert_pagerank_cache(conn, %{"lib/a.ex" => 0.8, "lib/b.ex" => 0.2}, 1_700_000)
    assert {:ok, cache} = Store.list_pagerank_cache(conn)
    assert cache["lib/a.ex"] == 0.8
    assert cache["lib/b.ex"] == 0.2

    assert :ok = Store.close(conn)
  end

  test "metadata is set and queried", %{path: path} do
    {:ok, conn} = Store.open(path)

    assert :ok = Store.set_meta(conn, "schema_version", "1")
    assert {:ok, "1"} = Store.get_meta(conn, "schema_version")

    assert :ok = Store.close(conn)
  end

  test "token signatures are upserted and read", %{path: path} do
    {:ok, conn} = Store.open(path)
    signature = <<9, 8, 7>>

    assert :ok = Store.upsert_token_signature(conn, "lib/a.ex", "MyModule", signature)
    assert {:ok, ^signature} = Store.get_token_signature(conn, "lib/a.ex", "MyModule")

    assert :ok = Store.close(conn)
  end
end
