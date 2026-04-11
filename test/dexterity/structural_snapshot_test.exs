defmodule Dexterity.StructuralSnapshotTest do
  use ExUnit.Case

  alias Dexterity.Store

  defmodule SnapshotBackend do
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
          line: 5
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
          line: 5
        }
      ],
      "lib/feature.ex" => [
        %{module: "MyApp.Feature", function: "run", arity: 1, file: "lib/feature.ex", line: 4},
        %{module: "MyApp.Feature", function: "bill", arity: 1, file: "lib/feature.ex", line: 8}
      ],
      "test/accounts_test.exs" => []
    }

    @impl true
    def list_file_edges(_repo_root) do
      {:ok,
       [
         {"lib/feature.ex", "lib/accounts.ex", 1.0},
         {"lib/feature.ex", "lib/payments.ex", 1.0}
       ]}
    end

    @impl true
    def list_file_nodes(_repo_root), do: {:ok, Map.keys(@symbols)}

    @impl true
    def list_exported_symbols(_repo_root, file), do: {:ok, Map.get(@symbols, file, [])}

    @impl true
    def list_symbol_nodes(_repo_root) do
      {:ok,
       [
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
       ]}
    end

    @impl true
    def list_symbol_edges(_repo_root) do
      {:ok,
       [
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
       ]}
    end

    @impl true
    def find_definition(_repo_root, _module, _function, _arity), do: {:error, :not_found}

    @impl true
    def find_references(_repo_root, "MyApp.Accounts", "register_user", 1),
      do: {:ok, [%{file: "lib/feature.ex", line: 5}]}

    @impl true
    def find_references(_repo_root, "MyApp.Accounts", "unused_helper", 0),
      do: {:ok, [%{file: "lib/accounts.ex", line: 9}]}

    @impl true
    def find_references(_repo_root, "MyApp.Payments", "capture_charge", 1),
      do: {:ok, [%{file: "lib/feature.ex", line: 9}]}

    @impl true
    def find_references(_repo_root, "MyApp.Payments", "refund_charge", 1), do: {:ok, []}

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
    repo_root =
      Path.join(
        System.tmp_dir!(),
        "dexterity-structural-snapshot-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(repo_root, "lib"))
    File.mkdir_p!(Path.join(repo_root, "test"))

    File.write!(
      Path.join(repo_root, "lib/accounts.ex"),
      """
      defmodule MyApp.Accounts do
        @moduledoc "Account registration and helper hooks."

        def register_user(attrs), do: attrs
        def unused_helper, do: :ok
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/payments.ex"),
      """
      defmodule MyApp.Payments do
        @moduledoc "Capture and refund flows."

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

        test "placeholder" do
          assert true
        end
      end
      """
    )

    store_path =
      Path.join(
        System.tmp_dir!(),
        "dexterity-structural-snapshot-#{System.unique_integer([:positive])}.db"
      )

    {:ok, conn} = Store.open(store_path)

    assert :ok =
             Store.upsert_runtime_observation(
               conn,
               "lib/accounts.ex",
               "MyApp.Accounts",
               "register_user",
               1,
               "cover",
               3,
               1_700_000
             )

    on_exit(fn ->
      Store.close(conn)
      File.rm(store_path)
      File.rm_rf(repo_root)
    end)

    %{repo_root: repo_root, store_conn: conn}
  end

  test "runtime observations are exposed through the public API", context do
    assert {:ok, observations} =
             Dexterity.get_runtime_observations(store_conn: context.store_conn)

    assert [
             %{
               file: "lib/accounts.ex",
               module: "MyApp.Accounts",
               function: "register_user",
               arity: 1,
               source: "cover",
               call_count: 3,
               observed_at: 1_700_000
             }
           ] = observations
  end

  test "file and symbol graph snapshots are exported with deterministic fingerprints", context do
    assert {:ok, file_graph} =
             Dexterity.get_file_graph_snapshot(
               backend: SnapshotBackend,
               repo_root: context.repo_root
             )

    assert {:ok, repeated_file_graph} =
             Dexterity.get_file_graph_snapshot(
               backend: SnapshotBackend,
               repo_root: context.repo_root
             )

    assert %Dexterity.FileGraphSnapshot{
             repo_root: repo_root,
             backend: "Dexterity.StructuralSnapshotTest.SnapshotBackend",
             files: files,
             edges: edges,
             fingerprint: fingerprint
           } = file_graph

    assert repo_root == Path.expand(context.repo_root)
    assert is_binary(fingerprint)
    assert fingerprint == repeated_file_graph.fingerprint

    assert Enum.any?(
             files,
             &(&1.file == "lib/feature.ex" and &1.metadata.modules == ["MyApp.Feature"])
           )

    assert Enum.any?(edges, &(&1.source == "lib/feature.ex" and &1.target == "lib/accounts.ex"))

    assert {:ok, symbol_graph} =
             Dexterity.get_symbol_graph_snapshot(
               backend: SnapshotBackend,
               repo_root: context.repo_root
             )

    assert {:ok, repeated_symbol_graph} =
             Dexterity.get_symbol_graph_snapshot(
               backend: SnapshotBackend,
               repo_root: context.repo_root
             )

    assert %Dexterity.SymbolGraphSnapshot{
             backend: "Dexterity.StructuralSnapshotTest.SnapshotBackend",
             nodes: nodes,
             edges: symbol_edges,
             source_snippets: snippets,
             fingerprint: symbol_fingerprint
           } = symbol_graph

    assert is_binary(symbol_fingerprint)
    assert symbol_fingerprint == repeated_symbol_graph.fingerprint

    assert Enum.any?(nodes, fn node ->
             node.id == "MyApp.Feature.run/1@lib/feature.ex" and
               node.signature == "def run(attrs)"
           end)

    assert Enum.any?(symbol_edges, fn edge ->
             edge.source_id == "MyApp.Feature.run/1@lib/feature.ex" and
               edge.target_id == "MyApp.Accounts.register_user/1@lib/accounts.ex"
           end)

    assert snippets["MyApp.Feature.run/1@lib/feature.ex"] =~ "Accounts.register_user"
  end

  test "combined structural snapshot includes optional export and runtime sections", context do
    assert {:ok, snapshot} =
             Dexterity.get_structural_snapshot(
               backend: SnapshotBackend,
               repo_root: context.repo_root,
               store_conn: context.store_conn,
               include_export_analysis: true,
               include_runtime_observations: true
             )

    assert {:ok, repeated_snapshot} =
             Dexterity.get_structural_snapshot(
               backend: SnapshotBackend,
               repo_root: context.repo_root,
               store_conn: context.store_conn,
               include_export_analysis: true,
               include_runtime_observations: true
             )

    assert %Dexterity.StructuralSnapshot{
             file_graph: %Dexterity.FileGraphSnapshot{},
             symbol_graph: %Dexterity.SymbolGraphSnapshot{},
             export_analysis: export_analysis,
             runtime_observations: observations,
             fingerprint: fingerprint
           } = snapshot

    assert is_binary(fingerprint)
    assert fingerprint == repeated_snapshot.fingerprint

    assert Enum.any?(export_analysis, fn export ->
             export.function == "register_user" and export.reachability == :production and
               export.runtime_call_count == 3 and export.runtime_sources == ["cover"]
           end)

    assert Enum.any?(
             export_analysis,
             &(&1.function == "refund_charge" and &1.reachability == :unused)
           )

    assert Enum.any?(observations, &(&1.function == "register_user" and &1.source == "cover"))
  end
end
