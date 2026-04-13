defmodule MixTasksTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Dexterity.ApplicationControl
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
      do: {:ok, [{"lib/a.ex", "lib/b.ex", 1.0}, {"lib/c.ex", "lib/b.ex", 0.5}]}

    @impl true
    def list_file_nodes(_repo_root),
      do: {:ok, ["lib/a.ex", "lib/b.ex", "lib/c.ex", "test/a_test.exs"]}

    @impl true
    def list_exported_symbols(_repo_root, "lib/a.ex") do
      {:ok,
       [
         %{module: "MyModule", function: "call", arity: 1, file: "lib/a.ex", line: 3},
         %{module: "MyModule", function: "unused_helper", arity: 0, file: "lib/a.ex", line: 6},
         %{module: "MyModule", function: "test_support", arity: 0, file: "lib/a.ex", line: 9}
       ]}
    end

    @impl true
    def list_exported_symbols(_repo_root, "lib/b.ex") do
      {:ok,
       [%{module: "Searchable", function: "register_user", arity: 1, file: "lib/b.ex", line: 4}]}
    end

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
    def find_references(_repo_root, "MyModule", "unused_helper", 0),
      do: {:ok, [%{file: "lib/a.ex", line: 12}]}

    @impl true
    def find_references(_repo_root, "MyModule", "test_support", 0),
      do: {:ok, [%{file: "test/a_test.exs", line: 5}]}

    @impl true
    def find_references(_repo_root, "Searchable", "register_user", 1), do: {:ok, []}

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
           module: "MyModule",
           function: "call",
           arity: 1,
           file: "lib/a.ex",
           line: 3,
           end_line: 5,
           visibility: :public,
           signature: "def call(input)",
           kind: "def"
         },
         %{
           module: "Searchable",
           function: "register_user",
           arity: 1,
           file: "lib/b.ex",
           line: 4,
           end_line: 4,
           visibility: :public,
           signature: "def register_user(attrs)",
           kind: "def"
         }
       ]}
    end

    @impl true
    def list_symbol_edges(_repo_root) do
      {:ok,
       [
         %{
           source: %{module: "MyModule", function: "call", arity: 1, file: "lib/a.ex", line: 3},
           target: %{
             module: "Searchable",
             function: "register_user",
             arity: 1,
             file: "lib/b.ex",
             line: 4
           },
           weight: 1.0
         }
       ]}
    end
  end

  defmodule RankedFilesTaskBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root) do
      {:ok,
       [
         {"lib/a.ex", "deps/dep_a/lib/dep_a.ex", 1.0},
         {"lib/b.ex", "deps/dep_a/lib/dep_a.ex", 1.0},
         {"deps/dep_b/lib/dep_b.ex", "deps/dep_a/lib/dep_a.ex", 1.0},
         {"deps/dep_a/lib/dep_a.ex", "deps/dep_b/lib/dep_b.ex", 0.7}
       ]}
    end

    @impl true
    def list_file_nodes(_repo_root) do
      {:ok, ["lib/a.ex", "lib/b.ex", "deps/dep_a/lib/dep_a.ex", "deps/dep_b/lib/dep_b.ex"]}
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
    stop_app_if_running()

    repo_root =
      Path.join(System.tmp_dir!(), "dexterity-mix-task-#{System.unique_integer([:positive])}")

    File.mkdir_p!(repo_root)

    on_exit(fn -> File.rm_rf(repo_root) end)

    %{repo_root: repo_root}
  end

  test "dexterity.index runs backend index command", %{repo_root: repo_root} do
    backend = TaskBackend

    output =
      capture_io(fn ->
        Index.run(["--repo-root", repo_root, "--backend", inspect(backend)])
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

  test "dexterity.status prints status snapshot", %{repo_root: repo_root} do
    backend = TaskBackend

    output =
      capture_io(fn ->
        Status.run(["--repo-root", repo_root, "--backend", inspect(backend)])
      end)

    assert output =~ "backend:"
    assert output =~ "graph_stale:"
  end

  test "dexterity.map writes result to output file", %{repo_root: repo_root} do
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
          repo_root,
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

  test "dexterity.query references/definition/blast/cochanges surfaces", %{repo_root: repo_root} do
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
          repo_root
        ])
      end)

    assert refs =~ "lib/caller.ex"

    defs =
      capture_io(fn ->
        Query.run([
          "definition",
          "MyModule",
          "--backend",
          inspect(backend),
          "--repo-root",
          repo_root
        ])
      end)

    assert defs =~ "MyModule"

    blast =
      capture_io(fn ->
        Query.run([
          "blast",
          "lib/a.ex",
          "--backend",
          inspect(backend),
          "--repo-root",
          repo_root
        ])
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
          repo_root,
          "--limit",
          "1"
        ])
      end)

    assert cochanges =~ "lib/b.ex"
    stop_app_if_running()
  end

  test "dexterity.query symbols/files/blast_count/ranked_symbols/impact_context/export_analysis/unused_exports/test_only_exports/structural snapshot surfaces",
       %{repo_root: repo_root} do
    backend = QueryTaskBackend

    store_path =
      Path.join(
        System.tmp_dir!(),
        "dexterity-mix-query-structural-store-#{:erlang.unique_integer([:positive])}.db"
      )

    previous_store_path = Application.get_env(:dexterity, :store_path)
    {:ok, conn} = Store.open(store_path)

    assert :ok =
             Store.upsert_runtime_observation(
               conn,
               "lib/a.ex",
               "MyModule",
               "call",
               1,
               "cover",
               2,
               1_700_000
             )

    Application.put_env(:dexterity, :store_path, store_path)

    on_exit(fn ->
      stop_app_if_running()
      Store.close(conn)
      restore_env(:dexterity, :store_path, previous_store_path)
      File.rm(store_path)
    end)

    symbols =
      capture_io(fn ->
        Query.run([
          "symbols",
          "register",
          "--backend",
          inspect(backend),
          "--repo-root",
          repo_root
        ])
      end)

    assert symbols =~ "register_user"

    files =
      capture_io(fn ->
        Query.run(["files", "%a%", "--backend", inspect(backend), "--repo-root", repo_root])
      end)

    assert files =~ "lib/a.ex"
    assert files =~ "test/a_test.exs"

    blast_count =
      capture_io(fn ->
        Query.run([
          "blast_count",
          "lib/b.ex",
          "--backend",
          inspect(backend),
          "--repo-root",
          repo_root
        ])
      end)

    assert blast_count =~ "2"

    ranked_symbols =
      capture_io(fn ->
        Query.run([
          "ranked_symbols",
          "--backend",
          inspect(backend),
          "--repo-root",
          repo_root,
          "--active-file",
          "lib/a.ex"
        ])
      end)

    assert ranked_symbols =~ "register_user"

    impact_context =
      capture_io(fn ->
        Query.run([
          "impact_context",
          "--backend",
          inspect(backend),
          "--repo-root",
          repo_root,
          "--changed-file",
          "lib/a.ex",
          "--token-budget",
          "512"
        ])
      end)

    assert impact_context =~ "MyModule.call/1"

    file_graph =
      capture_io(fn ->
        Query.run([
          "file_graph",
          "--backend",
          inspect(backend),
          "--repo-root",
          repo_root
        ])
      end)

    assert file_graph =~ "lib/a.ex"
    assert file_graph =~ "lib/b.ex"

    symbol_graph =
      capture_io(fn ->
        Query.run([
          "symbol_graph",
          "--backend",
          inspect(backend),
          "--repo-root",
          repo_root
        ])
      end)

    assert symbol_graph =~ "register_user"

    structural_snapshot =
      capture_io(fn ->
        Query.run([
          "structural_snapshot",
          "--backend",
          inspect(backend),
          "--repo-root",
          repo_root,
          "--include-export-analysis",
          "--include-runtime-observations"
        ])
      end)

    assert structural_snapshot =~ "file_graph"
    assert structural_snapshot =~ "runtime_observations"

    runtime_observations =
      capture_io(fn ->
        Query.run([
          "runtime_observations",
          "--backend",
          inspect(backend),
          "--repo-root",
          repo_root
        ])
      end)

    assert runtime_observations =~ "cover"

    unused =
      capture_io(fn ->
        Query.run(["unused_exports", "--backend", inspect(backend), "--repo-root", repo_root])
      end)

    assert unused =~ "unused_helper"

    export_analysis =
      capture_io(fn ->
        Query.run([
          "export_analysis",
          "--backend",
          inspect(backend),
          "--repo-root",
          repo_root
        ])
      end)

    assert export_analysis =~ "unused_helper"
    assert export_analysis =~ "public_api"

    test_only =
      capture_io(fn ->
        Query.run([
          "test_only_exports",
          "--backend",
          inspect(backend),
          "--repo-root",
          repo_root
        ])
      end)

    assert test_only =~ "test_support"
    stop_app_if_running()
  end

  test "dexterity.query ranked_files filters to first-party prefixes", %{repo_root: repo_root} do
    output =
      capture_io(fn ->
        Query.run([
          "ranked_files",
          "--backend",
          inspect(RankedFilesTaskBackend),
          "--repo-root",
          repo_root,
          "--include-prefix",
          "lib/",
          "--limit",
          "2"
        ])
      end)

    assert output =~ "ranked_files:"
    assert output =~ "lib/a.ex"
    assert output =~ "lib/b.ex"
    refute output =~ "deps/dep_a/lib/dep_a.ex"
  end

  defp stop_app_if_running do
    pid = Process.whereis(Dexterity.Supervisor)

    if is_pid(pid) do
      :ok = ApplicationControl.stop_quietly(:dexterity)
      wait_for_app_stop()
      :ok
    end

    :ok
  end

  defp wait_for_app_stop(attempts \\ 20)

  defp wait_for_app_stop(0), do: :ok

  defp wait_for_app_stop(attempts) do
    if Process.whereis(Dexterity.Supervisor) do
      Process.sleep(10)
      wait_for_app_stop(attempts - 1)
    else
      :ok
    end
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
