defmodule Dexterity.GraphServerTest do
  use ExUnit.Case

  alias Dexterity.GraphServer

  defmodule FakeBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root),
      do: {:ok, [{"lib/a.ex", "lib/b.ex", 1.2}, {"lib/b.ex", "lib/c.ex", 0.8}]}

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

  defmodule MetadataBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root), do: {:ok, []}

    @impl true
    def list_file_nodes(_repo_root) do
      {:ok,
       [
         "test/example_test.exs",
         "lib/support/data_case.ex",
         "lib/notifications.ex",
         "lib/notifications/email.ex",
         "lib/notifications/sms.ex"
       ]}
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
  end

  setup do
    name = Module.concat(__MODULE__, :"GraphServer#{:erlang.unique_integer([:positive])}")

    repo_root =
      Path.join(
        System.tmp_dir!(),
        "dexterity-graph-server-test-#{:erlang.unique_integer([:positive])}"
      )

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

  test "adds use, behaviour, and sibling implementation edges from source metadata" do
    name = Module.concat(__MODULE__, :"MetadataGraph#{:erlang.unique_integer([:positive])}")

    repo_root =
      Path.join(
        System.tmp_dir!(),
        "dexterity-metadata-graph-#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(repo_root, "lib/support"))
    File.mkdir_p!(Path.join(repo_root, "lib/notifications"))
    File.mkdir_p!(Path.join(repo_root, "test"))

    File.write!(
      Path.join(repo_root, "test/example_test.exs"),
      """
      defmodule ExampleTest do
        use MyApp.DataCase
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/support/data_case.ex"),
      """
      defmodule MyApp.DataCase do
        def setup_conn(conn), do: conn
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/notifications.ex"),
      """
      defmodule MyApp.Notifications do
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/notifications/email.ex"),
      """
      defmodule MyApp.Notifications.Email do
        @behaviour MyApp.Notifications
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/notifications/sms.ex"),
      """
      defmodule MyApp.Notifications.SMS do
        @behaviour MyApp.Notifications
      end
      """
    )

    start_supervised!(
      Supervisor.child_spec(
        {GraphServer,
         [
           repo_root: repo_root,
           backend: MetadataBackend,
           store_conn: nil,
           name: name
         ]},
        id: name
      )
    )

    Process.sleep(20)

    adjacency = GraphServer.get_adjacency(name)

    assert adjacency["test/example_test.exs"]["lib/support/data_case.ex"] == 3.0
    assert adjacency["lib/notifications/email.ex"]["lib/notifications.ex"] == 2.0
    assert adjacency["lib/notifications/email.ex"]["lib/notifications/sms.ex"] == 0.5
    assert adjacency["lib/notifications/sms.ex"]["lib/notifications/email.ex"] == 0.5

    File.rm_rf!(repo_root)
  end
end
