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

  test "cold_index builds a real dexter database for a repo" do
    dexter_bin = System.find_executable("dexter")
    repo_root = create_real_repo!()
    previous = Application.get_env(:dexterity, :dexter_bin)

    assert is_binary(dexter_bin)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:dexterity, :dexter_bin)
      else
        Application.put_env(:dexterity, :dexter_bin, previous)
      end

      File.rm_rf!(repo_root)
    end)

    Application.put_env(:dexterity, :dexter_bin, dexter_bin)

    assert :ok = Dexter.cold_index(repo_root)
    assert {:ok, :ready} = Dexter.index_status(repo_root)
    assert File.exists?(Path.join(repo_root, ".dexter.db"))

    assert {:ok, symbols} = Dexter.list_exported_symbols(repo_root, "lib/example.ex")
    assert Enum.any?(symbols, &(&1.module == "Example"))
    assert Enum.any?(symbols, &(&1.function == "hello"))
  end

  defp create_real_repo! do
    repo_root =
      Path.join(
        System.tmp_dir!(),
        "dexterity-backend-real-repo-#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(repo_root, "lib"))

    File.write!(
      Path.join(repo_root, "mix.exs"),
      """
      defmodule Example.MixProject do
        use Mix.Project

        def project do
          [
            app: :example,
            version: "0.1.0",
            elixir: "~> 1.18"
          ]
        end
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/example.ex"),
      """
      defmodule Example do
        def hello(name), do: {:ok, name}
      end
      """
    )

    repo_root
  end
end
