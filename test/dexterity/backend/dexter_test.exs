defmodule Dexterity.Backend.DexterTest do
  use ExUnit.Case
  alias Dexterity.Backend.Dexter

  @repo_root System.tmp_dir!()
  @db_path Path.join(@repo_root, ".dexter.db")

  setup do
    File.rm(@db_path)

    # Create a mock .dexter.db
    {:ok, conn} = Exqlite.Basic.open(@db_path)

    Exqlite.Basic.exec(
      conn,
      "CREATE TABLE definitions (module TEXT, function TEXT, arity INTEGER, file TEXT, line INTEGER)"
    )

    Exqlite.Basic.exec(
      conn,
      "CREATE TABLE \"references\" (caller_file TEXT, target_module TEXT, target_function TEXT, target_arity INTEGER)"
    )

    # Insert mock data
    Exqlite.Basic.exec(
      conn,
      "INSERT INTO definitions VALUES ('MyModule', 'my_func', 1, 'lib/my_module.ex', 10)"
    )

    Exqlite.Basic.exec(
      conn,
      "INSERT INTO \"references\" VALUES ('lib/caller.ex', 'MyModule', 'my_func', 1)"
    )

    Exqlite.Basic.exec(
      conn,
      "INSERT INTO \"references\" VALUES ('lib/caller.ex', 'MyModule', 'my_func', 1)"
    )

    Exqlite.Basic.exec(
      conn,
      "INSERT INTO \"references\" VALUES ('lib/caller.ex', 'MyModule', 'my_func', 1)"
    )

    Exqlite.Basic.close(conn)
    on_exit(fn -> File.rm(@db_path) end)
    :ok
  end

  test "list_file_edges calculates edges from references and definitions" do
    edges = Dexter.list_file_edges(@repo_root)
    assert length(edges) == 1

    {source, target, weight} = hd(edges)
    assert source == "lib/caller.ex"
    assert target == "lib/my_module.ex"
    # Weight should be sqrt(3) * 3.0 ≈ 1.732 * 3.0 = 5.196
    assert_in_delta weight, 5.196, 0.01
  end

  test "list_exported_symbols returns symbols for a given file" do
    symbols = Dexter.list_exported_symbols(@repo_root, "lib/my_module.ex")
    assert length(symbols) == 1
    assert hd(symbols).module == "MyModule"
    assert hd(symbols).function == "my_func"
    assert hd(symbols).arity == 1
  end

  test "index_status returns ready when .dexter.db exists" do
    assert Dexter.index_status(@repo_root) == :ready

    File.rm(@db_path)
    assert Dexter.index_status(@repo_root) == :missing
  end
end
