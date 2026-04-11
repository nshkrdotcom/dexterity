defmodule MixTasksTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Dexterity.Backend.Dexter
  alias Dexterity.Store
  alias Mix.Tasks.Dexterity.Index
  alias Mix.Tasks.Dexterity.Map, as: MapTask
  alias Mix.Tasks.Dexterity.Query
  alias Mix.Tasks.Dexterity.Status
  alias Mix.Tasks.Dexterity.TaskHelpers

  defmodule TaskBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root), do: {:ok, [{"lib/a.ex", "lib/b.ex", 1.0}]}

    @impl true
    def list_file_nodes(_repo_root), do: {:ok, ["lib/a.ex", "lib/b.ex"]}

    @impl true
    def list_exported_symbols(_repo_root, _file), do: {:ok, []}

    @impl true
    def find_definition(_repo_root, _module, _function, _arity), do: {:ok, []}

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

  defmodule QueryTaskBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root),
      do: {:ok, [{"lib/a.ex", "lib/b.ex", 1.0}, {"lib/b.ex", "lib/c.ex", 0.5}]}

    @impl true
    def list_file_nodes(_repo_root), do: {:ok, ["lib/a.ex", "lib/b.ex", "lib/c.ex"]}

    @impl true
    def list_exported_symbols(_repo_root, _file), do: {:ok, []}

    @impl true
    def find_definition(_repo_root, "MyModule", nil, nil),
      do: {:ok, [%{module: "MyModule", function: "call", arity: 1, file: "lib/a.ex", line: 3}]}

    @impl true
    def find_definition(_repo_root, _module, _function, _arity), do: {:error, :not_found}

    @impl true
    def find_references(_repo_root, "MyModule", nil, nil),
      do: {:ok, [%{file: "lib/caller.ex", line: 4}]}

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
    stop_app_if_running()
    :ok
  end

  test "dexterity.index runs backend index command" do
    backend = TaskBackend

    output =
      capture_io(fn ->
        Index.run(["--repo-root", "tmp", "--backend", inspect(backend)])
      end)

    assert output =~ "index refreshed"
  end

  test "task helpers load backend modules before validating callbacks" do
    unload_module!(Dexterity.Backend.Dexter)
    assert :code.is_loaded(Dexterity.Backend.Dexter) == false

    assert TaskHelpers.parse_backend(backend: "Dexterity.Backend.Dexter") ==
             Dexterity.Backend.Dexter
  end

  test "dexterity.index loads the configured backend and builds a real index" do
    dexter_bin = System.find_executable("dexter")
    repo_root = create_real_repo!()
    previous_bin = Application.get_env(:dexterity, :dexter_bin)

    assert is_binary(dexter_bin)

    on_exit(fn ->
      stop_app_if_running()
      restore_env(:dexterity, :dexter_bin, previous_bin)
      Code.ensure_loaded(Dexterity.Backend.Dexter)
      File.rm_rf(repo_root)
    end)

    Application.put_env(:dexterity, :dexter_bin, dexter_bin)
    unload_module!(Dexterity.Backend.Dexter)

    first_output =
      capture_io(fn ->
        Index.run(["--repo-root", repo_root])
      end)

    second_output =
      capture_io(fn ->
        Index.run(["--repo-root", repo_root])
      end)

    assert first_output =~ "index refreshed"
    assert second_output =~ "index refreshed"
    assert File.exists?(Path.join(repo_root, ".dexter.db"))
    assert {:ok, :ready} = Dexter.index_status(repo_root)
  end

  test "dexterity.status prints status snapshot" do
    backend = TaskBackend

    output =
      capture_io(fn ->
        Status.run(["--repo-root", "tmp", "--backend", inspect(backend)])
      end)

    assert output =~ "backend:"
    assert output =~ "graph_stale:"
  end

  test "dexterity.map writes result to output file" do
    tmp_file =
      Path.join(
        System.tmp_dir!(),
        "dexterity-map-task-#{:erlang.unique_integer([:positive])}.txt"
      )

    backend = TaskBackend

    output =
      capture_io(fn ->
        MapTask.run([
          "--repo-root",
          "tmp",
          "--backend",
          inspect(backend),
          "--output",
          tmp_file,
          "--limit",
          "10"
        ])
      end)

    assert output =~ "repo map written"
    assert File.exists?(tmp_file)
    assert File.read!(tmp_file) =~ "## lib/a.ex"
    on_exit(fn -> File.rm_rf(tmp_file) end)
  end

  test "dexterity.query references/definition/blast/cochanges surfaces" do
    backend = QueryTaskBackend

    store_path =
      Path.join(
        System.tmp_dir!(),
        "dexterity-mix-query-store-#{:erlang.unique_integer([:positive])}.db"
      )

    previous_store_path = Application.get_env(:dexterity, :store_path)
    {:ok, conn} = Store.open(store_path)
    assert :ok = Store.upsert_cochange(conn, "lib/a.ex", "lib/b.ex", 5, 2.4, 1_000)

    Application.put_env(:dexterity, :store_path, store_path)

    on_exit(fn ->
      stop_app_if_running()
      Store.close(conn)
      restore_env(:dexterity, :store_path, previous_store_path)
      File.rm(store_path)
    end)

    refs =
      capture_io(fn ->
        Query.run([
          "references",
          "MyModule",
          "--backend",
          inspect(backend),
          "--repo-root",
          "tmp"
        ])
      end)

    assert refs =~ "lib/caller.ex"

    defs =
      capture_io(fn ->
        Query.run(["definition", "MyModule", "--backend", inspect(backend), "--repo-root", "tmp"])
      end)

    assert defs =~ "MyModule"

    blast =
      capture_io(fn ->
        Query.run(["blast", "lib/a.ex", "--backend", inspect(backend), "--repo-root", "tmp"])
      end)

    assert blast =~ "lib/a.ex"

    cochanges =
      capture_io(fn ->
        Query.run([
          "cochanges",
          "lib/a.ex",
          "--backend",
          inspect(backend),
          "--repo-root",
          "tmp",
          "--limit",
          "1"
        ])
      end)

    assert cochanges =~ "lib/b.ex"
    stop_app_if_running()
  end

  defp stop_app_if_running do
    pid = Process.whereis(Dexterity.Supervisor)

    if is_pid(pid) do
      :ok = Application.stop(:dexterity)
      :ok
    end

    :ok
  end

  defp unload_module!(module) do
    :code.purge(module)
    :code.delete(module)
    :ok
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  defp create_real_repo! do
    repo_root =
      Path.join(
        System.tmp_dir!(),
        "dexterity-mix-task-repo-#{:erlang.unique_integer([:positive])}"
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
