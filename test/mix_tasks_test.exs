defmodule MixTasksTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Dexterity.Index
  alias Mix.Tasks.Dexterity.Map, as: MapTask
  alias Mix.Tasks.Dexterity.Query
  alias Mix.Tasks.Dexterity.Status

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
end
