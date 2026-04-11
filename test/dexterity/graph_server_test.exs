defmodule Dexterity.GraphServerTest do
  use ExUnit.Case

  alias Dexterity.GraphServer

  defmodule FakeBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root), do: {:ok, [{"lib/a.ex", "lib/b.ex", 1.2}, {"lib/b.ex", "lib/c.ex", 0.8}]}

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
    def index_status(_repo_root), do: {:ok, :missing}

    @impl true
    def healthy?(_repo_root), do: {:ok, true}
  end

  setup do
    name = Module.concat(__MODULE__, :"GraphServer#{:erlang.unique_integer([:positive])}")
    repo_root = Path.join(System.tmp_dir!(), "dexterity-graph-server-test-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(repo_root)

    {:ok, pid} =
      start_supervised(
        {GraphServer,
         [
           repo_root: repo_root,
           backend: FakeBackend,
           store_conn: nil,
           name: name
         ]}
      )

    Process.sleep(20)

    on_exit(fn -> File.rm_rf!(repo_root) end)

    %{server: name, pid: pid}
  end

  test "builds adjacency and ranking from backend edges", %{server: server} do
    assert {:ok, ranks} = GraphServer.get_repo_map(server, [], limit: 10)
    assert length(ranks) == 3
    assert MapSet.new(Enum.map(ranks, fn {file, _score} -> file end)) ==
             MapSet.new(["lib/a.ex", "lib/b.ex", "lib/c.ex"])

    assert %{"lib/a.ex" => adj_a, "lib/b.ex" => adj_b} = GraphServer.get_adjacency(server)
    assert adj_a["lib/b.ex"] == 1.2
    assert adj_b["lib/c.ex"] == 0.8
  end

  test "mark_stale rebuilds on next ranking call", %{server: server} do
    GraphServer.mark_stale(server)
    assert %{stale: true} = :sys.get_state(server) |> Map.take([:stale])

    assert {:ok, _ranks} = GraphServer.get_repo_map(server, [], limit: 10)
    assert %{stale: false} = :sys.get_state(server) |> Map.take([:stale])
  end
end
