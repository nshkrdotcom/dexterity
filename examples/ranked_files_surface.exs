defmodule Examples.RankedFilesSurface do
  alias Dexterity
  alias Dexterity.MCP
  alias Mix.Tasks.Dexterity.Query, as: QueryTask

  defmodule RankedFilesBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root) do
      {:ok,
       [
         {"lib/core.ex", "deps/dep_a/lib/dep_a.ex", 1.0},
         {"lib/feature.ex", "deps/dep_a/lib/dep_a.ex", 1.0},
         {"deps/dep_b/lib/dep_b.ex", "deps/dep_a/lib/dep_a.ex", 1.0},
         {"deps/dep_a/lib/dep_a.ex", "deps/dep_b/lib/dep_b.ex", 0.7}
       ]}
    end

    @impl true
    def list_file_nodes(_repo_root) do
      {:ok,
       ["lib/core.ex", "lib/feature.ex", "deps/dep_a/lib/dep_a.ex", "deps/dep_b/lib/dep_b.ex"]}
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

  def run do
    repo_root =
      Path.join(
        System.tmp_dir!(),
        "dexterity-ranked-files-surface-#{System.unique_integer([:positive])}"
      )

    create_fixture!(repo_root)

    {:ok, graph_server} =
      Dexterity.GraphServer.start_link(
        repo_root: repo_root,
        backend: RankedFilesBackend,
        store_conn: nil,
        name: nil
      )

    try do
      print_heading("Raw Ranked Files")

      IO.inspect(
        Dexterity.get_ranked_files(
          repo_root: repo_root,
          backend: RankedFilesBackend,
          graph_server: graph_server,
          active_file: "lib/core.ex",
          limit: 2
        ),
        pretty: true
      )

      print_heading("First-Party Ranked Files Via API")

      IO.inspect(
        Dexterity.get_ranked_files(
          repo_root: repo_root,
          backend: RankedFilesBackend,
          graph_server: graph_server,
          active_file: "lib/core.ex",
          include_prefixes: ["lib/"],
          exclude_prefixes: ["deps/"],
          overscan_limit: 10,
          limit: 2
        ),
        pretty: true
      )

      print_heading("First-Party Ranked Files Via Mix Task")

      run_mix_task!([
        "ranked_files",
        "--repo-root",
        repo_root,
        "--backend",
        inspect(RankedFilesBackend),
        "--active-file",
        "lib/core.ex",
        "--include-prefix",
        "lib/",
        "--exclude-prefix",
        "deps/",
        "--overscan-limit",
        "10",
        "--limit",
        "2"
      ])

      print_heading("First-Party Ranked Files Via MCP")

      {:ok, response} =
        MCP.handle_request(
          %{
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => "tools/call",
            "params" => %{
              "name" => "get_ranked_files",
              "arguments" => %{
                "backend" => inspect(RankedFilesBackend),
                "repo_root" => repo_root,
                "active_file" => "lib/core.ex",
                "include_prefixes" => ["lib/"],
                "exclude_prefixes" => ["deps/"],
                "overscan_limit" => 10,
                "limit" => 2
              }
            }
          },
          %{
            backend: RankedFilesBackend,
            repo_root: repo_root,
            graph_server: graph_server,
            symbol_graph_server: Dexterity.SymbolGraphServer
          }
        )

      IO.inspect(response, pretty: true)
    after
      GenServer.stop(graph_server, :normal, 5_000)
      File.rm_rf(repo_root)
    end
  end

  defp create_fixture!(repo_root) do
    files = %{
      "lib/core.ex" => """
      defmodule Demo.Core do
        def run, do: Demo.Feature.work()
      end
      """,
      "lib/feature.ex" => """
      defmodule Demo.Feature do
        def work, do: :ok
      end
      """,
      "deps/dep_a/lib/dep_a.ex" => """
      defmodule Demo.DepA do
        def helper, do: :ok
      end
      """,
      "deps/dep_b/lib/dep_b.ex" => """
      defmodule Demo.DepB do
        def helper, do: :ok
      end
      """
    }

    Enum.each(files, fn {path, contents} ->
      full_path = Path.join(repo_root, path)
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, contents)
    end)
  end

  defp run_mix_task!(args) do
    Mix.Task.reenable("dexterity.query")
    QueryTask.run(args)
  end

  defp print_heading(label) do
    IO.puts("\n=== #{label} ===")
  end
end

Examples.RankedFilesSurface.run()
