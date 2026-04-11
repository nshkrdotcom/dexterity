defmodule Dexterity.Backend.DexterTest do
  use ExUnit.Case

  alias Dexterity.Backend.Dexter
  alias Exqlite.Basic

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "dexterity-backend-test-#{:erlang.unique_integer([:positive])}"
      )

    db_path = Path.join(root, ".dexter.db")

    File.mkdir_p!(root)
    {:ok, conn} = Basic.open(db_path)

    {:ok, _query, _result, _} =
      Basic.exec(
        conn,
        "CREATE TABLE definitions (module TEXT, function TEXT, arity INTEGER, file TEXT, line INTEGER)"
      )

    {:ok, _query, _result, _} =
      Basic.exec(
        conn,
        "CREATE TABLE \"references\" (caller_file TEXT, target_module TEXT, target_function TEXT, target_arity INTEGER, line INTEGER)"
      )

    {:ok, _query, _result, _} =
      Basic.exec(
        conn,
        "INSERT INTO definitions VALUES ('MyModule', 'my_func', 1, 'lib/my_module.ex', 10)"
      )

    {:ok, _query, _result, _} =
      Basic.exec(
        conn,
        "INSERT INTO \"references\" VALUES ('lib/caller.ex', 'MyModule', 'my_func', 1, 12)"
      )

    {:ok, _query, _result, _} =
      Basic.exec(
        conn,
        "INSERT INTO \"references\" VALUES ('lib/caller.ex', 'MyModule', 'my_func', 1, 13)"
      )

    on_exit(fn ->
      Basic.close(conn)
      File.rm_rf!(root)
    end)

    %{repo_root: root}
  end

  test "list_file_edges returns weighted file graph edges", %{repo_root: repo_root} do
    assert {:ok, [{"lib/caller.ex", "lib/my_module.ex", _weight}]} =
             Dexter.list_file_edges(repo_root)
  end

  test "list_exported_symbols returns module symbols", %{repo_root: repo_root} do
    {:ok, symbols} = Dexter.list_exported_symbols(repo_root, "lib/my_module.ex")

    assert [
             %{
               arity: 1,
               file: "lib/my_module.ex",
               function: "my_func",
               line: 10,
               module: "MyModule"
             }
           ] = symbols
  end

  test "find_definition looks up exact and module-only matches", %{repo_root: repo_root} do
    assert {:ok, symbols} = Dexter.find_definition(repo_root, "MyModule", "my_func", 1)
    assert length(symbols) == 1

    assert {:ok, symbols} = Dexter.find_definition(repo_root, "MyModule", nil, nil)
    assert length(symbols) == 1
  end

  test "find_references resolves callers for exported symbol", %{repo_root: repo_root} do
    assert {:ok, refs} = Dexter.find_references(repo_root, "MyModule", "my_func", 1)
    assert [%{file: "lib/caller.ex", line: 12}, %{file: "lib/caller.ex", line: 13}] = refs
  end

  test "index_status reflects dexter database existence", %{repo_root: repo_root} do
    assert {:ok, :ready} = Dexter.index_status(repo_root)
    assert {:ok, :missing} = Dexter.index_status(repo_root <> "-missing")
  end

  test "healthy returns backend_missing_binary when dexter executable is unavailable" do
    assert {:error, :backend_missing_binary} = Dexter.healthy?(System.tmp_dir!())
  end
end
