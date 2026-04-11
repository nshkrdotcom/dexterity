defmodule Dexterity.QueryTest do
  use ExUnit.Case

  alias Dexterity.Query
  alias Dexterity.GraphServer

  defmodule QueryBackend do
    @behaviour Dexterity.Backend

    @definitions [
      %{
        module: "MyModule",
        function: "my_func",
        arity: 1,
        file: "lib/my_module.ex",
        line: 10
      }
    ]

    @references [
      %{module: "MyModule", function: "my_func", arity: 1, file: "lib/caller.ex", line: 3}
    ]

    @impl true
    def list_file_edges(_repo_root), do: {:ok, []}
    @impl true
    def list_file_nodes(_repo_root), do: {:ok, ["lib/my_module.ex"]}
    @impl true
    def list_exported_symbols(_repo_root, _file), do: {:ok, []}
    @impl true
    def find_definition(_repo_root, _module, _function, _arity), do: {:ok, @definitions}
    @impl true
    def find_references(_repo_root, _module, _function, _arity), do: {:ok, @references}
    @impl true
    def reindex_file(_file, _opts), do: :ok
    @impl true
    def cold_index(_repo_root, _opts), do: :ok
    @impl true
    def index_status(_repo_root), do: {:ok, :ready}
    @impl true
    def healthy?(_repo_root), do: {:ok, true}
  end

  defmodule BlastBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root), do: {:ok, []}
    @impl true
    def list_file_nodes(_repo_root), do: {:ok, []}
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
  end

  defmodule BlastGraphBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root), do: {:ok, [{"lib/a.ex", "lib/b.ex", 1.0}, {"lib/b.ex", "lib/c.ex", 1.0}]}
    @impl true
    def list_file_nodes(_repo_root), do: {:ok, ["lib/a.ex", "lib/b.ex", "lib/c.ex"]}
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
  end

  test "find_definition returns backend results" do
    assert {:ok, symbols} =
             Query.find_definition("MyModule", "my_func", 1, backend: QueryBackend)

    assert [%{module: "MyModule", function: "my_func", arity: 1, file: "lib/my_module.ex", line: 10}] =
             symbols
  end

  test "find_references returns caller references" do
    assert {:ok, refs} = Query.find_references("MyModule", "my_func", 1, backend: QueryBackend)
    assert [%{file: "lib/caller.ex", line: 3}] = refs
  end

  test "blast_radius traverses graph by file depth" do
    root = Path.join(System.tmp_dir!(), "dexterity-query-graph-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(root)

    name =
      Module.concat(__MODULE__, :"QueryGraph#{:erlang.unique_integer([:positive])}")

    {:ok, pid} =
      start_supervised(
        {GraphServer,
         [
           repo_root: root,
           backend: BlastGraphBackend,
           store_conn: nil,
           name: name
         ]}
      )

    Process.sleep(20)
    assert {:ok, results} = Query.blast_radius("lib/a.ex", graph_server: name, backend: BlastBackend, depth: 2)
    assert %{source: "lib/a.ex", depth: 0} in results
    assert %{source: "lib/b.ex", depth: 1} in results
    assert %{source: "lib/c.ex", depth: 2} in results

    on_exit(fn -> File.rm_rf!(root) end)
    _ = pid
  end

  test "cochanges returns top-N neighbor weights for file" do
    root = Path.join(System.tmp_dir!(), "dexterity-query-cochanges-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(root)

    name =
      Module.concat(__MODULE__, :"CochangeGraph#{:erlang.unique_integer([:positive])}")

    {:ok, pid} =
      start_supervised(
        {GraphServer,
         [
           repo_root: root,
           backend: BlastGraphBackend,
           store_conn: nil,
           name: name
         ]}
      )

    assert {:ok, [{"lib/b.ex", 1.0}]} = Query.cochanges("lib/a.ex", 5, graph_server: name)
    assert {:ok, [{"lib/c.ex", 1.0}]} = Query.cochanges("lib/b.ex", 1, graph_server: name)

    _ = pid
    on_exit(fn -> File.rm_rf!(root) end)
  end
end
