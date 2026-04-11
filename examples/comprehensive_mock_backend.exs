defmodule Examples.ComprehensiveMockBackend do
  @behaviour Dexterity.Backend

  @repo_files [
    "lib/my_app/accounts.ex",
    "lib/my_app/repo.ex",
    "lib/my_app/user.ex",
    "lib/my_app_web/live/dashboard_live.ex",
    "test/support/data_case.ex"
  ]

  @file_edges [
    {"lib/my_app_web/live/dashboard_live.ex", "lib/my_app/accounts.ex", 4.0},
    {"lib/my_app/accounts.ex", "lib/my_app/repo.ex", 3.0},
    {"lib/my_app/accounts.ex", "lib/my_app/user.ex", 2.0},
    {"test/support/data_case.ex", "lib/my_app/repo.ex", 1.0}
  ]

  @symbols_by_file %{
    "lib/my_app/accounts.ex" => [
      %{
        module: "MyApp.Accounts",
        function: "register_user",
        arity: 1,
        file: "lib/my_app/accounts.ex",
        line: 8
      },
      %{
        module: "MyApp.Accounts",
        function: "get_user!",
        arity: 1,
        file: "lib/my_app/accounts.ex",
        line: 14
      }
    ],
    "lib/my_app/repo.ex" => [
      %{module: "MyApp.Repo", function: "insert!", arity: 1, file: "lib/my_app/repo.ex", line: 2},
      %{module: "MyApp.Repo", function: "get!", arity: 2, file: "lib/my_app/repo.ex", line: 3}
    ],
    "lib/my_app/user.ex" => [
      %{
        module: "MyApp.User",
        function: "__struct__",
        arity: 0,
        file: "lib/my_app/user.ex",
        line: 2
      }
    ],
    "lib/my_app_web/live/dashboard_live.ex" => [
      %{
        module: "MyAppWeb.DashboardLive",
        function: "mount",
        arity: 3,
        file: "lib/my_app_web/live/dashboard_live.ex",
        line: 4
      }
    ]
  }

  @definitions [
    %{
      module: "MyApp.Accounts",
      function: "register_user",
      arity: 1,
      file: "lib/my_app/accounts.ex",
      line: 8
    },
    %{
      module: "MyApp.Accounts",
      function: "get_user!",
      arity: 1,
      file: "lib/my_app/accounts.ex",
      line: 14
    },
    %{module: "MyApp.Repo", function: "insert!", arity: 1, file: "lib/my_app/repo.ex", line: 2},
    %{module: "MyApp.Repo", function: "get!", arity: 2, file: "lib/my_app/repo.ex", line: 3}
  ]

  @references [
    %{
      module: "MyApp.Accounts",
      function: "register_user",
      arity: 1,
      file: "lib/my_app_web/live/dashboard_live.ex",
      line: 8
    },
    %{
      module: "MyApp.Accounts",
      function: "get_user!",
      arity: 1,
      file: "lib/my_app_web/live/dashboard_live.ex",
      line: 12
    }
  ]

  @impl true
  def list_file_edges(_repo_root), do: {:ok, @file_edges}

  @impl true
  def list_file_nodes(_repo_root), do: {:ok, @repo_files}

  @impl true
  def list_exported_symbols(_repo_root, file), do: {:ok, Map.get(@symbols_by_file, file, [])}

  @impl true
  def find_definition(_repo_root, module_name, function_name, arity) do
    matches =
      @definitions
      |> Enum.filter(&(&1.module == module_name))
      |> maybe_filter(:function, function_name)
      |> maybe_filter(:arity, arity)

    case matches do
      [] -> {:error, :not_found}
      entries -> {:ok, entries}
    end
  end

  @impl true
  def find_references(_repo_root, module_name, function_name, arity) do
    matches =
      @references
      |> Enum.filter(&(&1.module == module_name))
      |> maybe_filter(:function, function_name)
      |> maybe_filter(:arity, arity)
      |> Enum.map(&Map.take(&1, [:file, :line]))

    {:ok, matches}
  end

  @impl true
  def reindex_file(_file, _opts), do: :ok

  @impl true
  def cold_index(_repo_root, _opts), do: :ok

  @impl true
  def index_status(_repo_root), do: {:ok, :ready}

  @impl true
  def healthy?(_repo_root), do: {:ok, true}

  defp maybe_filter(entries, _key, nil), do: entries

  defp maybe_filter(entries, key, expected),
    do: Enum.filter(entries, &(Map.get(&1, key) == expected))
end

defmodule Examples.Comprehensive do
  alias Dexterity
  alias Dexterity.GraphServer
  alias Dexterity.Query
  alias Dexterity.Store
  alias Dexterity.SummaryWorker

  def run do
    repo_root =
      Path.join(
        System.tmp_dir!(),
        "dexterity-example-repo-#{:erlang.unique_integer([:positive])}"
      )

    store_path =
      Path.join(
        System.tmp_dir!(),
        "dexterity-example-store-#{:erlang.unique_integer([:positive])}.db"
      )

    graph_server = :"dexterity_example_graph_#{:erlang.unique_integer([:positive])}"
    summary_server = :"dexterity_example_summary_#{:erlang.unique_integer([:positive])}"

    try do
      create_repo!(repo_root)
      {:ok, conn} = Store.open(store_path)
      seed_cochanges!(conn)

      llm_parent = self()

      llm_fn = fn prompt ->
        send(llm_parent, {:summary_prompt, prompt})
        {:ok, "Coordinates user registration and retrieval."}
      end

      {:ok, _graph_pid} =
        GraphServer.start_link(
          repo_root: repo_root,
          backend: Examples.ComprehensiveMockBackend,
          store_conn: conn,
          name: graph_server
        )

      {:ok, _summary_pid} =
        SummaryWorker.start_link(
          name: summary_server,
          db_conn: conn,
          enabled: true,
          llm_fn: llm_fn,
          retry_delay_ms: 10
        )

      Process.sleep(25)

      print_heading("Repo Map (first pass)")

      {:ok, first_map} =
        Dexterity.get_repo_map(
          repo_root: repo_root,
          backend: Examples.ComprehensiveMockBackend,
          graph_server: graph_server,
          store_conn: conn,
          summary_server: summary_server,
          summary_enabled: true,
          active_file: "lib/my_app_web/live/dashboard_live.ex",
          mentioned_files: ["lib/my_app/accounts.ex"],
          token_budget: 2_500,
          limit: 5
        )

      IO.puts(first_map)
      wait_for_summary_prompt!()
      Process.sleep(25)

      print_heading("Repo Map (cached summary)")

      {:ok, second_map} =
        Dexterity.get_repo_map(
          repo_root: repo_root,
          backend: Examples.ComprehensiveMockBackend,
          graph_server: graph_server,
          store_conn: conn,
          summary_server: summary_server,
          summary_enabled: true,
          active_file: "lib/my_app_web/live/dashboard_live.ex",
          mentioned_files: ["lib/my_app/accounts.ex"],
          token_budget: 2_500,
          limit: 5
        )

      IO.puts(second_map)

      print_heading("Symbols")

      IO.inspect(
        Dexterity.get_symbols(
          "lib/my_app/accounts.ex",
          repo_root: repo_root,
          backend: Examples.ComprehensiveMockBackend
        ),
        pretty: true
      )

      print_heading("Definitions")

      IO.inspect(
        Query.find_definition(
          "MyApp.Accounts",
          "register_user",
          1,
          repo_root: repo_root,
          backend: Examples.ComprehensiveMockBackend
        ),
        pretty: true
      )

      print_heading("References")

      IO.inspect(
        Query.find_references(
          "MyApp.Accounts",
          "register_user",
          1,
          repo_root: repo_root,
          backend: Examples.ComprehensiveMockBackend
        ),
        pretty: true
      )

      print_heading("Module Dependencies")

      IO.inspect(
        Dexterity.get_module_deps(
          "lib/my_app/accounts.ex",
          graph: GraphServer.get_adjacency(graph_server)
        ),
        pretty: true
      )

      print_heading("Blast Radius")

      IO.inspect(
        Query.blast_radius("lib/my_app_web/live/dashboard_live.ex",
          graph_server: graph_server,
          depth: 2
        ),
        pretty: true
      )

      print_heading("Cochanges")

      IO.inspect(
        Query.cochanges("lib/my_app/accounts.ex", 5, graph_server: graph_server),
        pretty: true
      )

      print_heading("Cached PageRank")
      IO.inspect(Store.list_pagerank_cache(conn), pretty: true)

      :ok = Store.close(conn)
    after
      Process.whereis(graph_server) && GenServer.stop(graph_server)
      Process.whereis(summary_server) && GenServer.stop(summary_server)
      File.rm_rf(repo_root)
      File.rm(store_path)
    end
  end

  defp create_repo!(repo_root) do
    files = %{
      "lib/my_app/accounts.ex" => """
      defmodule MyApp.Accounts do
        alias MyApp.{Repo, User}

        @moduledoc "Account entry points."

        def register_user(attrs) do
          Repo.insert!(struct(User, attrs))
        end

        def get_user!(id) do
          Repo.get!(User, id)
        end
      end
      """,
      "lib/my_app/repo.ex" => """
      defmodule MyApp.Repo do
        def insert!(record), do: record
        def get!(module, id), do: struct(module, id: id)
      end
      """,
      "lib/my_app/user.ex" => """
      defmodule MyApp.User do
        defstruct [:id, :email]
      end
      """,
      "lib/my_app_web/live/dashboard_live.ex" => """
      defmodule MyAppWeb.DashboardLive do
        use Phoenix.LiveView
        alias MyApp.Accounts

        def mount(_params, _session, socket) do
          user = Accounts.register_user(%{email: "person@example.com"})
          {:ok, assign(socket, :user, user)}
        end
      end
      """,
      "test/support/data_case.ex" => """
      defmodule MyApp.DataCase do
        use ExUnit.CaseTemplate
        alias MyApp.Repo

        def build_user(id) do
          Repo.get!(MyApp.User, id)
        end
      end
      """
    }

    Enum.each(files, fn {relative_path, contents} ->
      full_path = Path.join(repo_root, relative_path)
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, contents)
    end)
  end

  defp seed_cochanges!(conn) do
    now = System.os_time(:second)

    :ok =
      Store.upsert_cochange(
        conn,
        "lib/my_app/accounts.ex",
        "lib/my_app_web/live/dashboard_live.ex",
        7,
        2.75,
        now
      )

    :ok =
      Store.upsert_cochange(
        conn,
        "lib/my_app/accounts.ex",
        "test/support/data_case.ex",
        4,
        1.2,
        now
      )
  end

  defp wait_for_summary_prompt! do
    receive do
      {:summary_prompt, prompt} ->
        print_heading("Summary Prompt")
        IO.puts(prompt)
    after
      1_000 ->
        raise "timed out waiting for summary worker"
    end
  end

  defp print_heading(label) do
    IO.puts("\n=== #{label} ===")
  end
end

Examples.Comprehensive.run()
