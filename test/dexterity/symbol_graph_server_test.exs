defmodule Dexterity.SymbolGraphServerTest do
  use ExUnit.Case

  alias Dexterity.SymbolGraphServer

  defmodule SymbolBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root), do: {:ok, []}

    @impl true
    def list_file_nodes(_repo_root) do
      {:ok, ["lib/a.ex", "lib/b.ex", "lib/c.ex"]}
    end

    @impl true
    def list_exported_symbols(_repo_root, _file), do: {:ok, []}

    @impl true
    def find_definition(_repo_root, _module, _function, _arity), do: {:error, :not_found}

    @impl true
    def find_references(_repo_root, _module, _function, _arity), do: {:ok, []}

    @impl true
    def reindex_file(_file, _opts), do: :ok

    @impl true
    def cold_index(_repo_root, _opts), do: :ok

    @impl true
    def index_status(_repo_root), do: {:ok, :ready}

    @impl true
    def healthy?(_repo_root), do: {:ok, true}

    @impl true
    def list_symbol_nodes(_repo_root) do
      {:ok,
       [
         %{
           module: "A",
           function: "run",
           arity: 0,
           file: "lib/a.ex",
           line: 1,
           visibility: :public,
           signature: "def run()",
           kind: "def"
         },
         %{
           module: "B",
           function: "calculate",
           arity: 1,
           file: "lib/b.ex",
           line: 1,
           visibility: :public,
           signature: "def calculate(input)",
           kind: "def"
         },
         %{
           module: "C",
           function: "persist",
           arity: 1,
           file: "lib/c.ex",
           line: 1,
           visibility: :public,
           signature: "def persist(result)",
           kind: "def"
         }
       ]}
    end

    @impl true
    def list_symbol_edges(_repo_root) do
      {:ok,
       [
         %{
           source: %{module: "A", function: "run", arity: 0, file: "lib/a.ex", line: 1},
           target: %{module: "B", function: "calculate", arity: 1, file: "lib/b.ex", line: 1},
           weight: 2.0
         },
         %{
           source: %{module: "B", function: "calculate", arity: 1, file: "lib/b.ex", line: 1},
           target: %{module: "C", function: "persist", arity: 1, file: "lib/c.ex", line: 1},
           weight: 1.0
         }
       ]}
    end
  end

  defmodule SlowSymbolBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root), do: {:ok, []}

    @impl true
    def list_file_nodes(_repo_root), do: {:ok, ["lib/a.ex"]}

    @impl true
    def list_exported_symbols(_repo_root, _file), do: {:ok, []}

    @impl true
    def find_definition(_repo_root, _module, _function, _arity), do: {:error, :not_found}

    @impl true
    def find_references(_repo_root, _module, _function, _arity), do: {:ok, []}

    @impl true
    def reindex_file(_file, _opts), do: :ok

    @impl true
    def cold_index(_repo_root, _opts), do: :ok

    @impl true
    def index_status(_repo_root), do: {:ok, :ready}

    @impl true
    def healthy?(_repo_root), do: {:ok, true}

    @impl true
    def list_symbol_nodes(_repo_root) do
      Process.sleep(50)

      {:ok,
       [
         %{
           module: "A",
           function: "run",
           arity: 0,
           file: "lib/a.ex",
           line: 1,
           visibility: :public,
           signature: "def run()",
           kind: "def"
         }
       ]}
    end

    @impl true
    def list_symbol_edges(_repo_root) do
      Process.sleep(50)
      {:ok, []}
    end
  end

  setup do
    name = Module.concat(__MODULE__, :"SymbolGraph#{System.unique_integer([:positive])}")

    repo_root =
      Path.join(System.tmp_dir!(), "dexterity-symbol-graph-#{System.unique_integer([:positive])}")

    File.mkdir_p!(repo_root)

    start_supervised!(
      {SymbolGraphServer,
       [
         repo_root: repo_root,
         backend: SymbolBackend,
         name: name
       ]}
    )

    Process.sleep(20)

    on_exit(fn -> File.rm_rf(repo_root) end)

    %{server: name}
  end

  test "builds symbol adjacency and ranks by symbol context", %{server: server} do
    assert {:ok, ranked} =
             SymbolGraphServer.get_ranked_symbols(
               server,
               %{symbols: [%{module: "A", function: "run", arity: 0}], files: []},
               limit: 10
             )

    assert [%{function: "run"} | _] = ranked

    assert Enum.any?(ranked, fn symbol ->
             symbol.function == "calculate" and symbol.module == "B" and is_float(symbol.rank)
           end)

    assert Enum.any?(ranked, fn symbol ->
             symbol.function == "persist" and symbol.module == "C"
           end)

    adjacency = SymbolGraphServer.get_adjacency(server)

    source_id =
      SymbolGraphServer.symbol_id(%{module: "A", function: "run", arity: 0, file: "lib/a.ex"})

    target_id =
      SymbolGraphServer.symbol_id(%{
        module: "B",
        function: "calculate",
        arity: 1,
        file: "lib/b.ex"
      })

    assert adjacency[source_id][target_id] == 2.0
  end

  test "resolves changed files to ranked impact symbols", %{server: server} do
    assert {:ok, ranked} =
             SymbolGraphServer.get_ranked_symbols(
               server,
               %{symbols: [], files: ["lib/a.ex"]},
               limit: 10
             )

    assert [%{file: "lib/a.ex", function: "run"} | _] = ranked
    assert Enum.any?(ranked, &(&1.file == "lib/b.ex" and &1.function == "calculate"))
  end

  test "supports longer call timeouts for slow symbol graph builds" do
    name = Module.concat(__MODULE__, :"SlowSymbolGraph#{System.unique_integer([:positive])}")

    repo_root =
      Path.join(System.tmp_dir!(), "dexterity-slow-symbol-#{System.unique_integer([:positive])}")

    File.mkdir_p!(repo_root)

    start_supervised!(
      Supervisor.child_spec(
        {SymbolGraphServer,
         [
           repo_root: repo_root,
           backend: SlowSymbolBackend,
           name: name
         ]},
        id: name
      )
    )

    on_exit(fn -> File.rm_rf!(repo_root) end)

    assert catch_exit(SymbolGraphServer.get_nodes(name, timeout: 10))
    assert nodes = SymbolGraphServer.get_nodes(name, timeout: 500)
    assert Enum.any?(nodes, fn {_id, symbol} -> symbol.module == "A" end)
  end
end
