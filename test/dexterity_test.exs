defmodule DexterityTest do
  use ExUnit.Case

  alias Dexterity
  alias Dexterity.GraphServer
  alias Dexterity.Store
  alias Dexterity.SummaryWorker

  defmodule StubBackend do
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
    def index_status(_repo_root), do: {:ok, :missing}

    @impl true
    def healthy?(_repo_root), do: {:ok, true}
  end

  defmodule SummaryBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root), do: {:ok, []}

    @impl true
    def list_file_nodes(_repo_root), do: {:ok, ["lib/my_module.ex"]}

    @impl true
    def list_exported_symbols(_repo_root, "lib/my_module.ex") do
      {:ok, [%{module: "MyModule", function: "run", arity: 1, file: "lib/my_module.ex", line: 3}]}
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

  test "notify_file_changed delegates to injected backend and marks graph stale" do
    assert Dexterity.notify_file_changed("lib/a.ex", backend: StubBackend) == :ok
  end

  test "get_symbols returns not_indexed when no exported symbols exist" do
    assert {:error, :not_indexed} =
             Dexterity.get_symbols("lib/does_not_exist.ex", backend: StubBackend)
  end

  test "get_repo_map enqueues and invalidates summaries based on mtime and signature" do
    repo_root =
      Path.join(System.tmp_dir!(), "dexterity-summary-#{:erlang.unique_integer([:positive])}")

    store_path =
      Path.join(
        System.tmp_dir!(),
        "dexterity-summary-store-#{:erlang.unique_integer([:positive])}.db"
      )

    graph_server = Module.concat(__MODULE__, :"GraphServer#{:erlang.unique_integer([:positive])}")

    summary_server =
      Module.concat(__MODULE__, :"SummaryWorker#{:erlang.unique_integer([:positive])}")

    file = "lib/my_module.ex"
    module_name = "MyModule"

    File.mkdir_p!(Path.join(repo_root, "lib"))

    File.write!(
      Path.join(repo_root, file),
      """
      defmodule MyModule do
        @moduledoc "Example summary input"
        def run(value), do: value
      end
      """
    )

    {:ok, conn} = Store.open(store_path)

    llm_parent = self()

    llm_fn = fn prompt ->
      send(llm_parent, {:llm_prompt, prompt})
      {:ok, "Caches the repo-map summary output."}
    end

    start_supervised!(
      {GraphServer,
       [
         repo_root: repo_root,
         backend: SummaryBackend,
         store_conn: nil,
         name: graph_server
       ]}
    )

    start_supervised!(
      {SummaryWorker,
       [
         name: summary_server,
         db_conn: conn,
         enabled: true,
         retry_delay_ms: 10,
         llm_fn: llm_fn
       ]}
    )

    Process.sleep(20)

    assert {:ok, first_map} =
             Dexterity.get_repo_map(
               backend: SummaryBackend,
               repo_root: repo_root,
               graph_server: graph_server,
               store_conn: conn,
               summary_server: summary_server,
               summary_enabled: true,
               limit: 10,
               token_budget: 1_000
             )

    refute first_map =~ "summary:"
    assert_receive {:llm_prompt, _prompt}, 1_000

    assert {:ok, second_map} =
             Dexterity.get_repo_map(
               backend: SummaryBackend,
               repo_root: repo_root,
               graph_server: graph_server,
               store_conn: conn,
               summary_server: summary_server,
               summary_enabled: true,
               limit: 10,
               token_budget: 1_000
             )

    assert second_map =~ "summary: Caches the repo-map summary output."
    assert {:ok, {summary, file_mtime, signature}} = Store.get_summary(conn, file, module_name)

    assert :ok =
             Store.upsert_summary(
               conn,
               file,
               module_name,
               summary,
               file_mtime - 1,
               signature,
               System.os_time(:second)
             )

    assert {:ok, stale_map} =
             Dexterity.get_repo_map(
               backend: SummaryBackend,
               repo_root: repo_root,
               graph_server: graph_server,
               store_conn: conn,
               summary_server: summary_server,
               summary_enabled: true,
               limit: 10,
               token_budget: 1_000
             )

    refute stale_map =~ "summary:"
    assert_receive {:llm_prompt, _prompt}, 1_000

    assert :ok =
             Store.upsert_summary(
               conn,
               file,
               module_name,
               summary,
               file_mtime,
               <<0, 1, 2>>,
               System.os_time(:second)
             )

    assert {:ok, mismatched_map} =
             Dexterity.get_repo_map(
               backend: SummaryBackend,
               repo_root: repo_root,
               graph_server: graph_server,
               store_conn: conn,
               summary_server: summary_server,
               summary_enabled: true,
               limit: 10,
               token_budget: 1_000
             )

    refute mismatched_map =~ "summary:"
    assert_receive {:llm_prompt, _prompt}, 1_000

    assert :ok = Store.close(conn)
    File.rm_rf!(repo_root)
    File.rm(store_path)
  end
end
