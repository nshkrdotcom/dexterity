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

  defmodule RuntimeBackend do
    @behaviour Dexterity.Backend

    @symbols %{
      "lib/accounts.ex" => [
        %{
          module: "MyApp.Accounts",
          function: "register_user",
          arity: 1,
          file: "lib/accounts.ex",
          line: 4
        },
        %{
          module: "MyApp.Accounts",
          function: "unused_helper",
          arity: 0,
          file: "lib/accounts.ex",
          line: 8
        },
        %{
          module: "MyApp.Accounts",
          function: "test_support_hook",
          arity: 0,
          file: "lib/accounts.ex",
          line: 12
        }
      ],
      "lib/payments.ex" => [
        %{
          module: "MyApp.Payments",
          function: "refund_charge",
          arity: 1,
          file: "lib/payments.ex",
          line: 4
        },
        %{
          module: "MyApp.Payments",
          function: "capture_charge",
          arity: 1,
          file: "lib/payments.ex",
          line: 8
        }
      ],
      "lib/feature.ex" => [
        %{
          module: "MyApp.Feature",
          function: "run",
          arity: 1,
          file: "lib/feature.ex",
          line: 4
        }
      ],
      "test/accounts_test.exs" => []
    }

    @references %{
      {"MyApp.Accounts", "register_user", 1} => [%{file: "lib/feature.ex", line: 5}],
      {"MyApp.Accounts", "unused_helper", 0} => [%{file: "lib/accounts.ex", line: 16}],
      {"MyApp.Accounts", "test_support_hook", 0} => [%{file: "test/accounts_test.exs", line: 7}],
      {"MyApp.Payments", "refund_charge", 1} => [],
      {"MyApp.Payments", "capture_charge", 1} => [%{file: "lib/feature.ex", line: 9}],
      {"MyApp.Feature", "run", 1} => []
    }

    @symbol_nodes [
      %{
        module: "MyApp.Accounts",
        function: "register_user",
        arity: 1,
        file: "lib/accounts.ex",
        line: 4,
        end_line: 4,
        visibility: :public,
        signature: "def register_user(attrs)",
        kind: "def"
      },
      %{
        module: "MyApp.Accounts",
        function: "unused_helper",
        arity: 0,
        file: "lib/accounts.ex",
        line: 5,
        end_line: 5,
        visibility: :public,
        signature: "def unused_helper()",
        kind: "def"
      },
      %{
        module: "MyApp.Accounts",
        function: "test_support_hook",
        arity: 0,
        file: "lib/accounts.ex",
        line: 6,
        end_line: 6,
        visibility: :public,
        signature: "def test_support_hook()",
        kind: "def"
      },
      %{
        module: "MyApp.Payments",
        function: "refund_charge",
        arity: 1,
        file: "lib/payments.ex",
        line: 4,
        end_line: 4,
        visibility: :public,
        signature: "def refund_charge(amount)",
        kind: "def"
      },
      %{
        module: "MyApp.Payments",
        function: "capture_charge",
        arity: 1,
        file: "lib/payments.ex",
        line: 5,
        end_line: 5,
        visibility: :public,
        signature: "def capture_charge(amount)",
        kind: "def"
      },
      %{
        module: "MyApp.Feature",
        function: "run",
        arity: 1,
        file: "lib/feature.ex",
        line: 4,
        end_line: 6,
        visibility: :public,
        signature: "def run(attrs)",
        kind: "def"
      },
      %{
        module: "MyApp.Feature",
        function: "bill",
        arity: 1,
        file: "lib/feature.ex",
        line: 8,
        end_line: 10,
        visibility: :public,
        signature: "def bill(amount)",
        kind: "def"
      }
    ]

    @symbol_edges [
      %{
        source: %{
          module: "MyApp.Feature",
          function: "run",
          arity: 1,
          file: "lib/feature.ex",
          line: 4
        },
        target: %{
          module: "MyApp.Accounts",
          function: "register_user",
          arity: 1,
          file: "lib/accounts.ex",
          line: 4
        },
        weight: 1.0
      },
      %{
        source: %{
          module: "MyApp.Feature",
          function: "bill",
          arity: 1,
          file: "lib/feature.ex",
          line: 8
        },
        target: %{
          module: "MyApp.Payments",
          function: "capture_charge",
          arity: 1,
          file: "lib/payments.ex",
          line: 5
        },
        weight: 1.0
      }
    ]

    @impl true
    def list_file_edges(_repo_root) do
      {:ok,
       [
         {"lib/feature.ex", "lib/accounts.ex", 1.0},
         {"test/accounts_test.exs", "lib/accounts.ex", 0.8},
         {"lib/feature.ex", "lib/payments.ex", 0.3}
       ]}
    end

    @impl true
    def list_file_nodes(_repo_root), do: {:ok, Map.keys(@symbols)}

    @impl true
    def list_exported_symbols(_repo_root, file), do: {:ok, Map.get(@symbols, file, [])}

    @impl true
    def find_definition(_repo_root, module, function, arity) do
      symbols =
        @symbols
        |> Map.values()
        |> List.flatten()
        |> Enum.filter(fn symbol ->
          symbol.module == module and symbol.function == function and symbol.arity == arity
        end)

      if symbols == [] do
        {:error, :not_found}
      else
        {:ok, symbols}
      end
    end

    @impl true
    def find_references(_repo_root, module, function, arity) do
      {:ok, Map.get(@references, {module, function, arity}, [])}
    end

    @impl true
    def reindex_file(_file, _opts), do: :ok

    @impl true
    def cold_index(_repo_root, _opts), do: :ok

    @impl true
    def index_status(_repo_root), do: {:ok, :ready}

    @impl true
    def healthy?(_repo_root), do: {:ok, true}

    @impl true
    def list_symbol_nodes(_repo_root), do: {:ok, @symbol_nodes}

    @impl true
    def list_symbol_edges(_repo_root), do: {:ok, @symbol_edges}
  end

  defmodule ScopedBackend do
    @behaviour Dexterity.Backend

    @nodes [
      "lib/core.ex",
      "lib/feature.ex",
      "deps/dep_a/lib/dep_a.ex",
      "deps/dep_b/lib/dep_b.ex"
    ]

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
    def list_file_nodes(_repo_root), do: {:ok, @nodes}

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

  defmodule SlowStopGraphServer do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    @impl true
    def init(opts) do
      {:ok,
       %{
         repo_root: Keyword.fetch!(opts, :repo_root),
         backend: Keyword.fetch!(opts, :backend),
         ranked: [{"lib/slow_stop.ex", 1.0}],
         terminate_delay_ms: Keyword.get(opts, :terminate_delay_ms, 50)
       }}
    end

    @impl true
    def handle_call(:get_metadata, _from, state), do: {:reply, %{}, state}

    @impl true
    def handle_call(:get_baseline_rank, _from, state), do: {:reply, %{}, state}

    @impl true
    def handle_call({:get_repo_map, _context_files, _opts}, _from, state) do
      {:reply, {:ok, state.ranked}, state}
    end

    @impl true
    def terminate(_reason, state) do
      Process.sleep(state.terminate_delay_ms)
      :ok
    end
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
    assert :ok = wait_for_summary_signature(conn, file, module_name, signature)

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

  test "get_ranked_files boosts files that match conversation terms" do
    repo_root = runtime_repo_root()
    graph_server = Module.concat(__MODULE__, :"RuntimeGraph#{System.unique_integer([:positive])}")

    start_supervised!(
      {GraphServer,
       [
         repo_root: repo_root,
         backend: RuntimeBackend,
         store_conn: nil,
         name: graph_server
       ]}
    )

    Process.sleep(20)

    assert {:ok, baseline} =
             Dexterity.get_ranked_files(
               backend: RuntimeBackend,
               repo_root: repo_root,
               graph_server: graph_server,
               limit: 10
             )

    assert {:ok, boosted} =
             Dexterity.get_ranked_files(
               backend: RuntimeBackend,
               repo_root: repo_root,
               graph_server: graph_server,
               conversation_terms: ["refund"],
               limit: 10
             )

    baseline_scores = Map.new(baseline)
    boosted_scores = Map.new(boosted)

    assert boosted_scores["lib/payments.ex"] > baseline_scores["lib/payments.ex"]
    assert hd(boosted) |> elem(0) == "lib/payments.ex"
  end

  test "get_ranked_files can overscan before filtering to first-party prefixes" do
    repo_root = runtime_repo_root()
    graph_server = Module.concat(__MODULE__, :"ScopedGraph#{System.unique_integer([:positive])}")

    start_supervised!(
      {GraphServer,
       [
         repo_root: repo_root,
         backend: ScopedBackend,
         store_conn: nil,
         name: graph_server
       ]}
    )

    Process.sleep(20)

    assert {:ok, [{"deps/dep_a/lib/dep_a.ex", _score}]} =
             Dexterity.get_ranked_files(
               backend: ScopedBackend,
               repo_root: repo_root,
               graph_server: graph_server,
               limit: 1
             )

    assert {:ok, [{"lib/" <> _path, _score}]} =
             Dexterity.get_ranked_files(
               backend: ScopedBackend,
               repo_root: repo_root,
               graph_server: graph_server,
               include_prefixes: ["lib/"],
               limit: 1
             )
  end

  test "get_ranked_files can exclude deps and keep the requested result count" do
    repo_root = runtime_repo_root()

    graph_server =
      Module.concat(__MODULE__, :"ScopedExcludeGraph#{System.unique_integer([:positive])}")

    start_supervised!(
      {GraphServer,
       [
         repo_root: repo_root,
         backend: ScopedBackend,
         store_conn: nil,
         name: graph_server
       ]}
    )

    Process.sleep(20)

    assert {:ok, filtered} =
             Dexterity.get_ranked_files(
               backend: ScopedBackend,
               repo_root: repo_root,
               graph_server: graph_server,
               exclude_prefixes: ["deps/"],
               limit: 2
             )

    assert length(filtered) == 2
    assert Enum.all?(filtered, fn {path, _score} -> String.starts_with?(path, "lib/") end)
  end

  test "get_ranked_files force stops a temporary graph server when graceful shutdown times out" do
    repo_root = runtime_repo_root()

    assert {:ok, [{"lib/slow_stop.ex", 1.0}]} =
             Dexterity.get_ranked_files(
               backend: StubBackend,
               repo_root: repo_root,
               graph_server: :missing_graph_server,
               graph_server_module: SlowStopGraphServer,
               temporary_server_stop_timeout: 10,
               limit: 1
             )
  end

  test "get_repo_map shrinks auto budget for long conversations" do
    repo_root = runtime_repo_root()
    graph_server = Module.concat(__MODULE__, :"BudgetGraph#{System.unique_integer([:positive])}")
    previous_min = Application.get_env(:dexterity, :min_token_budget)
    previous_default = Application.get_env(:dexterity, :default_token_budget)
    previous_max = Application.get_env(:dexterity, :max_token_budget)
    previous_saturation = Application.get_env(:dexterity, :token_budget_saturation_tokens)

    on_exit(fn ->
      restore_env(:dexterity, :min_token_budget, previous_min)
      restore_env(:dexterity, :default_token_budget, previous_default)
      restore_env(:dexterity, :max_token_budget, previous_max)
      restore_env(:dexterity, :token_budget_saturation_tokens, previous_saturation)
    end)

    Application.put_env(:dexterity, :min_token_budget, 18)
    Application.put_env(:dexterity, :default_token_budget, 72)
    Application.put_env(:dexterity, :max_token_budget, 72)
    Application.put_env(:dexterity, :token_budget_saturation_tokens, 10_000)

    start_supervised!(
      {GraphServer,
       [
         repo_root: repo_root,
         backend: RuntimeBackend,
         store_conn: nil,
         name: graph_server
       ]}
    )

    Process.sleep(20)

    assert {:ok, short_map} =
             Dexterity.get_repo_map(
               backend: RuntimeBackend,
               repo_root: repo_root,
               graph_server: graph_server,
               limit: 10,
               token_budget: :auto
             )

    assert {:ok, long_map} =
             Dexterity.get_repo_map(
               backend: RuntimeBackend,
               repo_root: repo_root,
               graph_server: graph_server,
               limit: 10,
               token_budget: :auto,
               conversation_tokens: 200_000
             )

    assert occurrences(short_map, "## ") > occurrences(long_map, "## ")
  end

  test "runtime search and export analysis surfaces return ranked indexed results" do
    repo_root = runtime_repo_root()

    graph_server =
      Module.concat(__MODULE__, :"AnalysisGraph#{System.unique_integer([:positive])}")

    start_supervised!(
      {GraphServer,
       [
         repo_root: repo_root,
         backend: RuntimeBackend,
         store_conn: nil,
         name: graph_server
       ]}
    )

    Process.sleep(20)

    assert {:ok, [%{function: "refund_charge", file: "lib/payments.ex", rank: rank} | _]} =
             Dexterity.find_symbols(
               "refund",
               backend: RuntimeBackend,
               repo_root: repo_root,
               graph_server: graph_server
             )

    assert is_float(rank)

    assert {:ok, ["lib/accounts.ex", "test/accounts_test.exs"]} =
             Dexterity.match_files(
               "%accounts%",
               backend: RuntimeBackend,
               repo_root: repo_root,
               graph_server: graph_server
             )

    assert {:ok, 2} =
             Dexterity.get_file_blast_radius(
               "lib/accounts.ex",
               backend: RuntimeBackend,
               repo_root: repo_root,
               graph_server: graph_server
             )

    assert {:ok, unused_exports} =
             Dexterity.get_unused_exports(
               backend: RuntimeBackend,
               repo_root: repo_root,
               graph_server: graph_server
             )

    assert Enum.any?(unused_exports, fn export ->
             export.function == "unused_helper" and export.used_internally == true
           end)

    assert Enum.any?(unused_exports, fn export ->
             export.function == "refund_charge" and export.used_internally == false
           end)

    assert {:ok, test_only_exports} =
             Dexterity.get_test_only_exports(
               backend: RuntimeBackend,
               repo_root: repo_root,
               graph_server: graph_server
             )

    assert Enum.any?(test_only_exports, fn export ->
             export.function == "test_support_hook" and export.file == "lib/accounts.ex"
           end)
  end

  test "symbol ranking and diff-aware impact context return symbol-level context" do
    repo_root = runtime_repo_root()

    graph_server =
      Module.concat(__MODULE__, :"ImpactGraph#{System.unique_integer([:positive])}")

    symbol_graph_server =
      Module.concat(__MODULE__, :"ImpactSymbolGraph#{System.unique_integer([:positive])}")

    start_supervised!(
      {GraphServer,
       [
         repo_root: repo_root,
         backend: RuntimeBackend,
         store_conn: nil,
         name: graph_server
       ]}
    )

    start_supervised!(
      {Dexterity.SymbolGraphServer,
       [
         repo_root: repo_root,
         backend: RuntimeBackend,
         name: symbol_graph_server
       ]}
    )

    Process.sleep(20)

    assert {:ok, ranked_symbols} =
             Dexterity.get_ranked_symbols(
               active_file: "lib/feature.ex",
               backend: RuntimeBackend,
               repo_root: repo_root,
               symbol_graph_server: symbol_graph_server
             )

    assert Enum.any?(ranked_symbols, fn symbol ->
             symbol.function == "run" and symbol.module == "MyApp.Feature"
           end)

    assert {:ok, impact_context} =
             Dexterity.get_impact_context(
               changed_files: ["lib/feature.ex"],
               backend: RuntimeBackend,
               repo_root: repo_root,
               graph_server: graph_server,
               symbol_graph_server: symbol_graph_server,
               token_budget: 2_000
             )

    assert impact_context =~ "### MyApp.Feature.run/1 [CHANGED]"
    assert impact_context =~ "register_user"
    assert impact_context =~ "capture_charge"
  end

  defp runtime_repo_root do
    repo_root =
      Path.join(System.tmp_dir!(), "dexterity-runtime-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(repo_root, "lib"))
    File.mkdir_p!(Path.join(repo_root, "test"))

    File.write!(
      Path.join(repo_root, "lib/accounts.ex"),
      """
      defmodule MyApp.Accounts do
        @moduledoc "Account operations and internal helper hooks."

        def register_user(attrs), do: attrs
        def unused_helper, do: audit_trail()
        def test_support_hook, do: :ok

        defp audit_trail, do: :ok
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/payments.ex"),
      """
      defmodule MyApp.Payments do
        @moduledoc "Refund and capture workflows."

        def refund_charge(amount), do: {:ok, amount}
        def capture_charge(amount), do: {:captured, amount}
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/feature.ex"),
      """
      defmodule MyApp.Feature do
        alias MyApp.{Accounts, Payments}

        def run(attrs) do
          Accounts.register_user(attrs)
        end

        def bill(amount) do
          Payments.capture_charge(amount)
        end
      end
      """
    )

    File.write!(
      Path.join(repo_root, "test/accounts_test.exs"),
      """
      defmodule MyApp.AccountsTest do
        use ExUnit.Case
        alias MyApp.Accounts

        test "test support hook remains callable" do
          assert Accounts.test_support_hook() == :ok
        end
      end
      """
    )

    on_exit(fn -> File.rm_rf!(repo_root) end)
    repo_root
  end

  defp occurrences(string, pattern) do
    Regex.scan(~r/#{Regex.escape(pattern)}/, string) |> length()
  end

  defp wait_for_summary_signature(conn, file, module_name, expected_signature, attempts \\ 20)

  defp wait_for_summary_signature(_conn, _file, _module_name, _expected_signature, 0) do
    {:error, :summary_timeout}
  end

  defp wait_for_summary_signature(conn, file, module_name, expected_signature, attempts) do
    case Store.get_summary(conn, file, module_name) do
      {:ok, {_summary, _mtime, ^expected_signature}} ->
        :ok

      _ ->
        Process.sleep(20)
        wait_for_summary_signature(conn, file, module_name, expected_signature, attempts - 1)
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
