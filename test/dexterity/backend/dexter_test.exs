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
    module_path = Path.join(root, "lib/my_module.ex")
    caller_path = Path.join(root, "lib/caller.ex")

    File.mkdir_p!(root)
    {:ok, conn} = Basic.open(db_path)

    {:ok, _query, _result, _} =
      Basic.exec(
        conn,
        """
        CREATE TABLE definitions (
          module TEXT,
          function TEXT,
          arity INTEGER,
          kind TEXT,
          line INTEGER,
          file_path TEXT
        )
        """
      )

    {:ok, _query, _result, _} =
      Basic.exec(
        conn,
        """
        CREATE TABLE refs (
          module TEXT,
          function TEXT,
          line INTEGER,
          file_path TEXT,
          kind TEXT
        )
        """
      )

    {:ok, _query, _result, _} =
      Basic.exec(
        conn,
        "INSERT INTO definitions VALUES ('MyModule', '', 0, 'module', 1, ?1)",
        [module_path]
      )

    {:ok, _query, _result, _} =
      Basic.exec(
        conn,
        "INSERT INTO definitions VALUES ('MyModule', 'my_func', 1, 'function', 10, ?1)",
        [module_path]
      )

    {:ok, _query, _result, _} =
      Basic.exec(
        conn,
        "INSERT INTO refs VALUES ('MyModule', 'my_func', 12, ?1, 'call')",
        [caller_path]
      )

    {:ok, _query, _result, _} =
      Basic.exec(
        conn,
        "INSERT INTO refs VALUES ('MyModule', 'my_func', 13, ?1, 'call')",
        [caller_path]
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
    assert hd(symbols).function == ""
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
    previous = Application.get_env(:dexterity, :dexter_bin)
    Application.put_env(:dexterity, :dexter_bin, "definitely-not-a-real-dexter-binary")

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:dexterity, :dexter_bin)
      else
        Application.put_env(:dexterity, :dexter_bin, previous)
      end
    end)

    assert {:error, :backend_missing_binary} = Dexter.healthy?(System.tmp_dir!())
  end
end
