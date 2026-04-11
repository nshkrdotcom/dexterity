defmodule Examples.ComprehensiveRealBackend do
  alias Dexterity
  alias Dexterity.MCP
  alias Dexterity.Query
  alias Mix.Tasks.Dexterity.Index, as: IndexTask
  alias Mix.Tasks.Dexterity.Map, as: MapTask
  alias Mix.Tasks.Dexterity.Query, as: QueryTask
  alias Mix.Tasks.Dexterity.Status, as: StatusTask

  @config_keys [
    :repo_root,
    :backend,
    :dexter_bin,
    :store_path,
    :cochange_enabled,
    :cochange_min_frequency,
    :cochange_commit_depth,
    :cochange_interval_ms,
    :summary_enabled,
    :mcp_enabled
  ]

  def run do
    dexter_bin = detect_dexter!()
    id = :erlang.unique_integer([:positive])
    repo_root = Path.join(System.tmp_dir!(), "dexterity-real-example-#{id}")
    store_path = Path.join(System.tmp_dir!(), "dexterity-real-example-store-#{id}.db")
    map_output_path = Path.join(System.tmp_dir!(), "dexterity-real-example-map-#{id}.md")
    previous = snapshot_config()
    app_was_running = Process.whereis(Dexterity.Supervisor) != nil

    try do
      create_repo!(repo_root)
      seed_git_history!(repo_root)
      configure_runtime(repo_root, store_path, dexter_bin)
      build_index!(repo_root)
      start_dexterity!()

      # Let the background cochange worker ingest git history, then force a rebuild.
      Process.sleep(300)
      Dexterity.GraphServer.mark_stale()
      Process.sleep(100)

      run_mix_tasks!(repo_root, map_output_path)

      print_heading("Dexter CLI")
      IO.puts(run_cmd!(dexter_bin, ["version"], repo_root))
      IO.puts(run_cmd!(dexter_bin, ["lookup", "MyApp.Accounts", "register_user"], repo_root))
      IO.puts(run_cmd!(dexter_bin, ["references", "MyApp.Accounts", "register_user"], repo_root))

      print_heading("Ranked Files")

      ranked =
        Dexterity.get_ranked_files(
          active_file: "lib/my_app_web/live/dashboard_live.ex",
          mentioned_files: ["lib/my_app/accounts.ex"],
          limit: 20
        )

      IO.inspect(filter_project_files(ranked), pretty: true)

      print_heading("Term-Aware Ranked Files")

      ranked_with_terms =
        Dexterity.get_ranked_files(
          active_file: "lib/my_app_web/live/dashboard_live.ex",
          mentioned_files: ["lib/my_app/accounts.ex"],
          conversation_terms: ["refund"],
          limit: 20
        )

      IO.inspect(filter_project_files(ranked_with_terms), pretty: true)

      print_heading("Status")
      IO.inspect(Dexterity.status(), pretty: true)

      print_heading("Repo Map")

      {:ok, repo_map} =
        Dexterity.get_repo_map(
          active_file: "lib/my_app_web/live/dashboard_live.ex",
          mentioned_files: ["lib/my_app/accounts.ex"],
          edited_files: ["test/support/data_case.ex"],
          conversation_terms: ["refund", "support"],
          conversation_tokens: 150_000,
          limit: 5,
          token_budget: :auto,
          include_clones: true
        )

      IO.puts(repo_map)

      print_heading("Symbols")
      IO.inspect(Dexterity.get_symbols("lib/my_app/accounts.ex"), pretty: true)

      print_heading("Definition")
      IO.inspect(Query.find_definition("MyApp.Accounts", "register_user", 1), pretty: true)

      print_heading("References")
      IO.inspect(Query.find_references("MyApp.Accounts", "register_user", 1), pretty: true)

      print_heading("Module Dependencies")
      IO.inspect(Dexterity.get_module_deps("lib/my_app/accounts.ex"), pretty: true)

      print_heading("Symbol Search")
      IO.inspect(Dexterity.find_symbols("refund"), pretty: true)

      print_heading("Indexed File Match")
      IO.inspect(Dexterity.match_files("%accounts%"), pretty: true)

      print_heading("Direct Blast Radius")
      IO.inspect(Dexterity.get_file_blast_radius("lib/my_app/accounts.ex"), pretty: true)

      print_heading("Blast Radius")

      IO.inspect(Query.blast_radius("lib/my_app_web/live/dashboard_live.ex", depth: 2),
        pretty: true
      )

      print_heading("Cochanges")
      IO.inspect(Query.cochanges("lib/my_app/accounts.ex", 5), pretty: true)

      print_heading("Unused Exports")
      IO.inspect(Dexterity.get_unused_exports(), pretty: true)

      print_heading("Test-Only Exports")
      IO.inspect(Dexterity.get_test_only_exports(), pretty: true)

      print_heading("Real Reindex")
      touch_live_view!(repo_root)
      :ok = Dexterity.notify_file_changed("lib/my_app_web/live/dashboard_live.ex")
      IO.inspect(Query.find_references("MyApp.Accounts", "get_user!", 1), pretty: true)

      run_mcp_demo(repo_root)
    after
      if Process.whereis(Dexterity.Supervisor) do
        Application.stop(:dexterity)
      end

      restore_config(previous)

      if app_was_running do
        Application.ensure_all_started(:dexterity)
      end

      File.rm_rf(repo_root)
      File.rm(store_path)
      File.rm(map_output_path)
    end
  end

  defp detect_dexter! do
    case System.get_env("DEXTER_BIN") || System.find_executable("dexter") do
      nil ->
        raise """
        dexter executable not found.

        Install Dexter and make sure it is on PATH, or run with:
          DEXTER_BIN=/absolute/path/to/dexter mix run examples/comprehensive_real_backend.exs
        """

      path ->
        path
    end
  end

  defp snapshot_config do
    Map.new(@config_keys, fn key ->
      {key, Application.get_env(:dexterity, key)}
    end)
  end

  defp restore_config(previous) do
    Enum.each(previous, fn
      {key, nil} -> Application.delete_env(:dexterity, key)
      {key, value} -> Application.put_env(:dexterity, key, value)
    end)
  end

  defp configure_runtime(repo_root, store_path, dexter_bin) do
    Application.put_env(:dexterity, :repo_root, repo_root)
    Application.put_env(:dexterity, :backend, Dexterity.Backend.Dexter)
    Application.put_env(:dexterity, :dexter_bin, dexter_bin)
    Application.put_env(:dexterity, :store_path, store_path)
    Application.put_env(:dexterity, :cochange_enabled, true)
    Application.put_env(:dexterity, :cochange_min_frequency, 1)
    Application.put_env(:dexterity, :cochange_commit_depth, 20)
    Application.put_env(:dexterity, :cochange_interval_ms, 60_000)
    Application.put_env(:dexterity, :summary_enabled, false)
    Application.put_env(:dexterity, :mcp_enabled, false)
  end

  defp start_dexterity! do
    if Process.whereis(Dexterity.Supervisor) do
      :ok = Application.stop(:dexterity)
    end

    {:ok, _apps} = Application.ensure_all_started(:dexterity)
  end

  defp create_repo!(repo_root) do
    files = %{
      "mix.exs" => """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [
            app: :my_app,
            version: "0.1.0",
            elixir: "~> 1.18"
          ]
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
      "lib/my_app/accounts.ex" => """
      defmodule MyApp.Accounts do
        alias MyApp.{Repo, User}

        @moduledoc "Account entry points for the example repo."

        def register_user(attrs) do
          Repo.insert!(struct(User, attrs))
        end

        def get_user!(id) do
          Repo.get!(User, id)
        end

        def test_support_user(id) do
          get_user!(id)
        end
      end
      """,
      "lib/my_app/payments.ex" => """
      defmodule MyApp.Payments do
        @moduledoc "Billing and refund entry points for the example repo."

        def capture_charge(amount_cents) do
          {:captured, amount_cents}
        end

        def refund_charge(amount_cents) do
          {:refunded, amount_cents}
        end
      end
      """,
      "lib/my_app_web/live/dashboard_live.ex" => """
      defmodule MyAppWeb.DashboardLive do
        use Phoenix.LiveView
        alias MyApp.{Accounts, Payments}

        def mount(_params, _session, socket) do
          user = Accounts.register_user(%{email: "person@example.com"})
          Payments.capture_charge(500)
          {:ok, assign(socket, :user, user)}
        end
      end
      """,
      "test/support/data_case.ex" => """
      defmodule MyApp.DataCase do
        use ExUnit.CaseTemplate
        alias MyApp.{Accounts, Repo, User}

        def build_user(id) do
          Accounts.test_support_user(id)
          Repo.get!(User, id)
        end
      end
      """,
      "test/my_app/accounts_test.exs" => """
      defmodule MyApp.AccountsTest do
        use ExUnit.Case
        alias MyApp.Accounts

        test "test helper stays reachable" do
          assert %{id: 1} = Accounts.test_support_user(1)
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

  defp seed_git_history!(repo_root) do
    git!(repo_root, ["init", "-b", "main"])
    git!(repo_root, ["config", "user.name", "Dexterity Example"])
    git!(repo_root, ["config", "user.email", "example@dexterity.dev"])
    git!(repo_root, ["config", "commit.gpgsign", "false"])

    git!(repo_root, ["add", "."])
    git!(repo_root, ["commit", "-m", "Initial project skeleton"])

    append!(repo_root, "lib/my_app/accounts.ex", "\n  def list_users, do: [:ok]\n")

    append!(
      repo_root,
      "lib/my_app_web/live/dashboard_live.ex",
      "\n  def handle_params(_, _, socket), do: {:noreply, socket}\n"
    )

    git!(repo_root, ["add", "."])
    git!(repo_root, ["commit", "-m", "Expand accounts and live view together"])

    append!(repo_root, "lib/my_app/accounts.ex", "\n  def repo_name, do: MyApp.Repo\n")
    append!(repo_root, "test/support/data_case.ex", "\n  def repo_module, do: MyApp.Repo\n")

    git!(repo_root, ["add", "."])
    git!(repo_root, ["commit", "-m", "Touch accounts and data case together"])
  end

  defp build_index!(repo_root) do
    print_heading("Mix Task: dexterity.index")
    run_mix_task!("dexterity.index", IndexTask, ["--repo-root", repo_root])
  end

  defp run_mix_tasks!(repo_root, map_output_path) do
    print_heading("Mix Task: dexterity.status")
    run_mix_task!("dexterity.status", StatusTask, ["--repo-root", repo_root])

    print_heading("Mix Task: dexterity.map")

    run_mix_task!("dexterity.map", MapTask, [
      "--repo-root",
      repo_root,
      "--active-file",
      "lib/my_app_web/live/dashboard_live.ex",
      "--mentioned-file",
      "lib/my_app/accounts.ex",
      "--edited-file",
      "test/support/data_case.ex",
      "--limit",
      "5",
      "--token-budget",
      "3000",
      "--include-clones",
      "--output",
      map_output_path
    ])

    IO.puts(File.read!(map_output_path))

    print_heading("Mix Task: dexterity.query definition")

    run_mix_task!("dexterity.query", QueryTask, [
      "definition",
      "MyApp.Accounts",
      "register_user",
      "1",
      "--repo-root",
      repo_root
    ])

    print_heading("Mix Task: dexterity.query references")

    run_mix_task!("dexterity.query", QueryTask, [
      "references",
      "MyApp.Accounts",
      "register_user",
      "1",
      "--repo-root",
      repo_root
    ])

    print_heading("Mix Task: dexterity.query blast")

    run_mix_task!("dexterity.query", QueryTask, [
      "blast",
      "lib/my_app_web/live/dashboard_live.ex",
      "--repo-root",
      repo_root,
      "--depth",
      "2"
    ])

    print_heading("Mix Task: dexterity.query cochanges")

    run_mix_task!("dexterity.query", QueryTask, [
      "cochanges",
      "lib/my_app/accounts.ex",
      "--repo-root",
      repo_root,
      "--limit",
      "5"
    ])

    print_heading("Mix Task: dexterity.query symbols")

    run_mix_task!("dexterity.query", QueryTask, [
      "symbols",
      "refund",
      "--repo-root",
      repo_root
    ])

    print_heading("Mix Task: dexterity.query files")

    run_mix_task!("dexterity.query", QueryTask, [
      "files",
      "%accounts%",
      "--repo-root",
      repo_root
    ])

    print_heading("Mix Task: dexterity.query blast_count")

    run_mix_task!("dexterity.query", QueryTask, [
      "blast_count",
      "lib/my_app/accounts.ex",
      "--repo-root",
      repo_root
    ])

    print_heading("Mix Task: dexterity.query unused_exports")

    run_mix_task!("dexterity.query", QueryTask, [
      "unused_exports",
      "--repo-root",
      repo_root
    ])

    print_heading("Mix Task: dexterity.query test_only_exports")

    run_mix_task!("dexterity.query", QueryTask, [
      "test_only_exports",
      "--repo-root",
      repo_root
    ])
  end

  defp run_mcp_demo(repo_root) do
    context = %{
      backend: Dexterity.Backend.Dexter,
      repo_root: repo_root,
      graph_server: Dexterity.GraphServer
    }

    print_heading("MCP initialize")

    mcp_request!(%{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{"info" => "comprehensive_real_backend"}
    }, context)

    print_heading("MCP tools/list")
    mcp_request!(%{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"}, context)

    print_heading("MCP tools/call status")

    mcp_request!(%{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call",
      "params" => %{"name" => "status", "arguments" => %{}}
    }, context)

    print_heading("MCP tools/call get_repo_map")

    mcp_request!(%{
      "jsonrpc" => "2.0",
      "id" => 4,
      "method" => "tools/call",
      "params" => %{
        "name" => "get_repo_map",
        "arguments" => %{
          "active_file" => "lib/my_app/accounts.ex",
          "mentioned_files" => ["lib/my_app_web/live/dashboard_live.ex"],
          "token_budget" => 2048,
          "limit" => 5
        }
      }
    }, context)

    print_heading("MCP tools/call find_symbols")

    mcp_request!(%{
      "jsonrpc" => "2.0",
      "id" => 5,
      "method" => "tools/call",
      "params" => %{
        "name" => "find_symbols",
        "arguments" => %{"query" => "refund"}
      }
    }, context)

    print_heading("MCP tools/call get_unused_exports")

    mcp_request!(%{
      "jsonrpc" => "2.0",
      "id" => 6,
      "method" => "tools/call",
      "params" => %{
        "name" => "get_unused_exports",
        "arguments" => %{}
      }
    }, context)
  end

  defp mcp_request!(request, context) do
    request
    |> Jason.encode!()
    |> MCP.process_line(context)
  end

  defp run_mix_task!(task_name, module, args) do
    Mix.Task.reenable(task_name)
    module.run(args)
  end

  defp touch_live_view!(repo_root) do
    append!(
      repo_root,
      "lib/my_app_web/live/dashboard_live.ex",
      "\n  def lookup_user(id), do: MyApp.Accounts.get_user!(id)\n"
    )
  end

  defp append!(repo_root, relative_path, content) do
    path = Path.join(repo_root, relative_path)
    File.write!(path, content, [:append])
  end

  defp git!(repo_root, args) do
    _output = run_cmd!("git", args, repo_root)
  end

  defp run_cmd!(cmd, args, repo_root) do
    case System.cmd(cmd, args, cd: repo_root, stderr_to_stdout: true) do
      {output, 0} ->
        String.trim(output)

      {output, exit_code} ->
        raise """
        command failed: #{cmd} #{Enum.join(args, " ")}
        exit: #{exit_code}
        output:
        #{output}
        """
    end
  end

  defp filter_project_files({:ok, ranked_files}) do
    {:ok,
     ranked_files
     |> Enum.filter(fn {file, _score} ->
       String.starts_with?(file, "lib/") or
         String.starts_with?(file, "test/") or
         file == "mix.exs"
     end)
     |> Enum.take(8)}
  end

  defp print_heading(label) do
    IO.puts("\n=== #{label} ===")
  end
end

Examples.ComprehensiveRealBackend.run()
