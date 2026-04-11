defmodule Dexterity.ExportReachabilityTest do
  use ExUnit.Case

  alias Dexterity.GraphServer
  alias Dexterity.Store

  defmodule ReachabilityBackend do
    @behaviour Dexterity.Backend

    @symbols %{
      "mix.exs" => [
        %{module: "MyApp.MixProject", function: "project", arity: 0, file: "mix.exs", line: 4},
        %{
          module: "MyApp.MixProject",
          function: "application",
          arity: 0,
          file: "mix.exs",
          line: 11
        }
      ],
      "lib/my_app/application.ex" => [
        %{
          module: "MyApp.Application",
          function: "start",
          arity: 2,
          file: "lib/my_app/application.ex",
          line: 5
        }
      ],
      "lib/my_app/worker.ex" => [
        %{
          module: "MyApp.Worker",
          function: "start_link",
          arity: 1,
          file: "lib/my_app/worker.ex",
          line: 4
        },
        %{
          module: "MyApp.Worker",
          function: "init",
          arity: 1,
          file: "lib/my_app/worker.ex",
          line: 9
        }
      ],
      "lib/my_app/public_api.ex" => [
        %{
          module: "MyApp.PublicApi",
          function: "public_call",
          arity: 0,
          file: "lib/my_app/public_api.ex",
          line: 2
        },
        %{
          module: "MyApp.PublicApi",
          function: "test_only_call",
          arity: 0,
          file: "lib/my_app/public_api.ex",
          line: 3
        },
        %{
          module: "MyApp.PublicApi",
          function: "internal_only_call",
          arity: 0,
          file: "lib/my_app/public_api.ex",
          line: 4
        },
        %{
          module: "MyApp.PublicApi",
          function: "unused_call",
          arity: 0,
          file: "lib/my_app/public_api.ex",
          line: 5
        }
      ],
      "lib/my_app_web/live/dashboard_live.ex" => [
        %{
          module: "MyAppWeb.DashboardLive",
          function: "mount",
          arity: 3,
          file: "lib/my_app_web/live/dashboard_live.ex",
          line: 5
        }
      ],
      "lib/my_app/covered.ex" => [
        %{
          module: "MyApp.Covered",
          function: "observed_runtime",
          arity: 0,
          file: "lib/my_app/covered.ex",
          line: 2
        },
        %{
          module: "MyApp.Covered",
          function: "unobserved_runtime",
          arity: 0,
          file: "lib/my_app/covered.ex",
          line: 3
        }
      ],
      "lib/my_app/user_string_chars.ex" => [
        %{
          module: "String.Chars.MyApp.User",
          function: "to_string",
          arity: 1,
          file: "lib/my_app/user_string_chars.ex",
          line: 2
        }
      ]
    }

    @references %{
      {"MyApp.PublicApi", "public_call", 0} => [%{file: "lib/my_app/consumer.ex", line: 3}],
      {"MyApp.PublicApi", "test_only_call", 0} => [
        %{file: "test/my_app/public_api_test.exs", line: 3}
      ],
      {"MyApp.PublicApi", "internal_only_call", 0} => [
        %{file: "lib/my_app/public_api.ex", line: 7}
      ],
      {"MyApp.PublicApi", "unused_call", 0} => [],
      {"MyApp.Covered", "observed_runtime", 0} => [],
      {"MyApp.Covered", "unobserved_runtime", 0} => []
    }

    @impl true
    def list_file_edges(_repo_root), do: {:ok, []}

    @impl true
    def list_file_nodes(_repo_root) do
      {:ok,
       [
         "mix.exs",
         "lib/my_app/application.ex",
         "lib/my_app/worker.ex",
         "lib/my_app/public_api.ex",
         "lib/my_app/consumer.ex",
         "lib/my_app/covered.ex",
         "lib/my_app/user.ex",
         "lib/my_app/user_string_chars.ex",
         "lib/my_app_web/live/dashboard_live.ex",
         "test/my_app/public_api_test.exs"
       ]}
    end

    @impl true
    def list_exported_symbols(_repo_root, file), do: {:ok, Map.get(@symbols, file, [])}

    @impl true
    def find_definition(_repo_root, module, function, arity) do
      matches =
        @symbols
        |> Map.values()
        |> List.flatten()
        |> Enum.filter(fn symbol ->
          symbol.module == module and symbol.function == function and symbol.arity == arity
        end)

      if matches == [], do: {:error, :not_found}, else: {:ok, matches}
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
  end

  setup do
    repo_root =
      Path.join(
        System.tmp_dir!(),
        "dexterity-export-reachability-#{System.unique_integer([:positive])}"
      )

    store_path =
      Path.join(
        System.tmp_dir!(),
        "dexterity-export-reachability-#{System.unique_integer([:positive])}.db"
      )

    File.rm(store_path)
    write_repo_fixture!(repo_root)

    {:ok, store_conn} = Store.open(store_path)

    graph_server =
      Module.concat(__MODULE__, :"GraphServer#{System.unique_integer([:positive])}")

    start_supervised!(
      {GraphServer,
       [
         repo_root: repo_root,
         backend: ReachabilityBackend,
         store_conn: nil,
         name: graph_server
       ]}
    )

    Process.sleep(20)

    on_exit(fn ->
      Store.close(store_conn)
      File.rm(store_path)
      File.rm_rf(repo_root)
      stop_cover()
      purge_module(MyApp.Covered)
    end)

    %{repo_root: repo_root, store_conn: store_conn, graph_server: graph_server}
  end

  test "classifies callback entrypoints separately from ordinary public api", context do
    assert {:ok, analysis} =
             Dexterity.get_export_analysis(
               backend: ReachabilityBackend,
               repo_root: context.repo_root,
               graph_server: context.graph_server,
               store_conn: context.store_conn
             )

    exports =
      Map.new(analysis, fn export -> {{export.module, export.function, export.arity}, export} end)

    assert exports[{"MyAppWeb.DashboardLive", "mount", 3}].kind == :callback_entrypoint
    assert exports[{"MyAppWeb.DashboardLive", "mount", 3}].reachability == :callback

    assert "use Phoenix.LiveView" in exports[{"MyAppWeb.DashboardLive", "mount", 3}].entrypoint_sources

    assert exports[{"MyApp.MixProject", "project", 0}].kind == :callback_entrypoint
    assert exports[{"MyApp.MixProject", "project", 0}].reachability == :callback
    assert "use Mix.Project" in exports[{"MyApp.MixProject", "project", 0}].entrypoint_sources

    assert exports[{"MyApp.Application", "start", 2}].kind == :callback_entrypoint
    assert exports[{"MyApp.Application", "start", 2}].reachability == :callback

    assert "behaviour Application" in exports[{"MyApp.Application", "start", 2}].entrypoint_sources

    assert exports[{"MyApp.Worker", "init", 1}].kind == :callback_entrypoint
    assert exports[{"MyApp.Worker", "init", 1}].reachability == :callback
    assert "behaviour GenServer" in exports[{"MyApp.Worker", "init", 1}].entrypoint_sources

    assert exports[{"String.Chars.MyApp.User", "to_string", 1}].kind == :callback_entrypoint
    assert exports[{"String.Chars.MyApp.User", "to_string", 1}].reachability == :callback

    assert "protocol String.Chars" in exports[{"String.Chars.MyApp.User", "to_string", 1}].entrypoint_sources

    assert exports[{"MyApp.PublicApi", "public_call", 0}].kind == :public_api
    assert exports[{"MyApp.PublicApi", "public_call", 0}].reachability == :production
    assert exports[{"MyApp.PublicApi", "test_only_call", 0}].reachability == :test_only
    assert exports[{"MyApp.PublicApi", "internal_only_call", 0}].reachability == :internal_only
    assert exports[{"MyApp.PublicApi", "unused_call", 0}].reachability == :unused
  end

  test "unused and test-only filters are backed by the richer reachability model", context do
    assert {:ok, unused_exports} =
             Dexterity.get_unused_exports(
               backend: ReachabilityBackend,
               repo_root: context.repo_root,
               graph_server: context.graph_server,
               store_conn: context.store_conn
             )

    assert Enum.any?(unused_exports, &(&1.function == "unused_call"))

    assert Enum.any?(
             unused_exports,
             &(&1.function == "internal_only_call" and &1.used_internally)
           )

    refute Enum.any?(unused_exports, &(&1.function == "mount"))
    refute Enum.any?(unused_exports, &(&1.function == "project"))
    refute Enum.any?(unused_exports, &(&1.function == "start"))
    refute Enum.any?(unused_exports, &(&1.function == "init"))
    refute Enum.any?(unused_exports, &(&1.function == "to_string"))

    assert {:ok, test_only_exports} =
             Dexterity.get_test_only_exports(
               backend: ReachabilityBackend,
               repo_root: context.repo_root,
               graph_server: context.graph_server,
               store_conn: context.store_conn
             )

    assert [%{function: "test_only_call"}] =
             Enum.filter(test_only_exports, &(&1.function == "test_only_call"))

    refute Enum.any?(test_only_exports, &(&1.function == "mount"))
  end

  test "cover observations can be imported and reclassify runtime-observed exports", context do
    assert {:ok, before} =
             Dexterity.get_export_analysis(
               backend: ReachabilityBackend,
               repo_root: context.repo_root,
               graph_server: context.graph_server,
               store_conn: context.store_conn
             )

    before_map =
      Map.new(before, fn export -> {{export.module, export.function, export.arity}, export} end)

    assert before_map[{"MyApp.Covered", "observed_runtime", 0}].reachability == :unused

    beam_dir = Path.join(context.repo_root, "_build/export_reachability")
    File.mkdir_p!(beam_dir)

    covered_source = Path.join(context.repo_root, "lib/my_app/covered.ex")

    {"", 0} =
      System.cmd("elixirc", ["-o", beam_dir, covered_source], stderr_to_stdout: true)

    Code.prepend_path(beam_dir)
    assert {:module, MyApp.Covered} = Code.ensure_loaded(MyApp.Covered)

    ensure_cover_tools!()

    case cover_apply(:start, []) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    beam_path = Path.join(beam_dir, "Elixir.MyApp.Covered.beam")
    assert {:ok, MyApp.Covered} = cover_apply(:compile_beam, [String.to_charlist(beam_path)])

    assert :seen = Function.capture(MyApp.Covered, :observed_runtime, 0).()

    assert {:ok, recorded} =
             Dexterity.import_cover_modules(
               [MyApp.Covered],
               backend: ReachabilityBackend,
               repo_root: context.repo_root,
               graph_server: context.graph_server,
               store_conn: context.store_conn
             )

    assert recorded >= 1

    assert {:ok, after_import} =
             Dexterity.get_export_analysis(
               backend: ReachabilityBackend,
               repo_root: context.repo_root,
               graph_server: context.graph_server,
               store_conn: context.store_conn
             )

    after_map =
      Map.new(after_import, fn export ->
        {{export.module, export.function, export.arity}, export}
      end)

    assert after_map[{"MyApp.Covered", "observed_runtime", 0}].reachability == :runtime
    assert after_map[{"MyApp.Covered", "observed_runtime", 0}].runtime_call_count >= 1
    assert after_map[{"MyApp.Covered", "unobserved_runtime", 0}].reachability == :unused
  end

  defp write_repo_fixture!(repo_root) do
    File.mkdir_p!(Path.join(repo_root, "lib/my_app"))
    File.mkdir_p!(Path.join(repo_root, "lib/my_app_web/live"))
    File.mkdir_p!(Path.join(repo_root, "test/my_app"))

    File.write!(
      Path.join(repo_root, "mix.exs"),
      """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [
            app: :my_app,
            version: "0.1.0"
          ]
        end

        def application do
          [extra_applications: [:logger]]
        end
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/my_app/application.ex"),
      """
      defmodule MyApp.Application do
        use Application

        @impl true
        def start(_type, _args) do
          Supervisor.start_link([], strategy: :one_for_one)
        end
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/my_app/worker.ex"),
      """
      defmodule MyApp.Worker do
        use GenServer

        def start_link(arg) do
          GenServer.start_link(__MODULE__, arg, name: __MODULE__)
        end

        @impl true
        def init(arg), do: {:ok, arg}
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/my_app/public_api.ex"),
      """
      defmodule MyApp.PublicApi do
        def public_call, do: :ok
        def test_only_call, do: :ok
        def internal_only_call, do: support_internal_only()
        def unused_call, do: :unused

        defp support_internal_only, do: internal_only_call()
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/my_app/consumer.ex"),
      """
      defmodule MyApp.Consumer do
        alias MyApp.PublicApi

        def run, do: PublicApi.public_call()
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/my_app/covered.ex"),
      """
      defmodule MyApp.Covered do
        def observed_runtime, do: :seen
        def unobserved_runtime, do: :unseen
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/my_app/user.ex"),
      """
      defmodule MyApp.User do
        defstruct [:id]
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/my_app/user_string_chars.ex"),
      """
      defimpl String.Chars, for: MyApp.User do
        def to_string(_user), do: "user"
      end
      """
    )

    File.write!(
      Path.join(repo_root, "lib/my_app_web/live/dashboard_live.ex"),
      """
      defmodule MyAppWeb.DashboardLive do
        use Phoenix.LiveView

        @impl true
        def mount(_params, _session, socket), do: {:ok, socket}
      end
      """
    )

    File.write!(
      Path.join(repo_root, "test/my_app/public_api_test.exs"),
      """
      defmodule MyApp.PublicApiTest do
        test "test support path" do
          MyApp.PublicApi.test_only_call()
        end
      end
      """
    )
  end

  defp purge_module(module) do
    :code.purge(module)
    :code.delete(module)
    :ok
  end

  defp ensure_cover_tools! do
    if tools_ebin = cover_ebin_path() do
      :code.add_pathz(String.to_charlist(tools_ebin))
    end

    assert {:module, :cover} = :code.ensure_loaded(:cover)
  end

  defp stop_cover do
    ensure_cover_tools!()

    case cover_apply(:stop, []) do
      {:error, :not_main_node} -> :ok
      {:error, :not_started} -> :ok
      {:error, {:not_main_node, _node}} -> :ok
      _ -> :ok
    end
  end

  defp cover_apply(function_name, args) do
    :erlang.apply(:cover, function_name, args)
  end

  defp cover_ebin_path do
    :code.root_dir()
    |> to_string()
    |> Path.join("lib/tools-*/ebin")
    |> Path.wildcard()
    |> Enum.sort()
    |> List.first()
  end
end
