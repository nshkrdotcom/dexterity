defmodule Dexterity.GraphTest do
  use ExUnit.Case

  alias Dexterity.Graph
  alias Dexterity.GraphServer

  defmodule GraphTestBackend do
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

  setup do
    root = Path.join(System.tmp_dir!(), "dexterity-graph-mod-test-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(root)

    name =
      Module.concat(__MODULE__, :"GraphServer#{:erlang.unique_integer([:positive])}")

    {:ok, pid} =
      start_supervised(
        {GraphServer,
         [
           repo_root: root,
           backend: GraphTestBackend,
           store_conn: nil,
           name: name
         ]}
      )

    on_exit(fn ->
      File.rm_rf!(root)
    end)

    %{name: name, pid: pid}
  end

  test "get_adjacency returns tagged result", %{name: name} do
    assert {:ok, adjacency} = Graph.get_adjacency(server: name)
    assert adjacency["lib/a.ex"]["lib/b.ex"] == 1.0
    assert adjacency["lib/b.ex"]["lib/c.ex"] == 1.0
  end
end
