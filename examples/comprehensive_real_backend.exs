defmodule Examples.ComprehensiveRealBackend do
  alias Dexterity
  alias Dexterity.Query

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
    previous = snapshot_config()
    app_was_running = Process.whereis(Dexterity.Supervisor) != nil

    try do
      create_repo!(repo_root)
      seed_git_history!(repo_root)
      build_index!(dexter_bin, repo_root)
      restart_dexterity!(repo_root, store_path, dexter_bin)

      # Let the background cochange worker ingest git history, then force a rebuild.
      Process.sleep(300)
      Dexterity.GraphServer.mark_stale()
      Process.sleep(100)

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

      print_heading("Status")
      IO.inspect(Dexterity.status(), pretty: true)

      print_heading("Repo Map")

      {:ok, repo_map} =
        Dexterity.get_repo_map(
          active_file: "lib/my_app_web/live/dashboard_live.ex",
          mentioned_files: ["lib/my_app/accounts.ex"],
          edited_files: ["test/support/data_case.ex"],
          limit: 8,
          token_budget: 3_000,
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

      print_heading("Blast Radius")

      IO.inspect(Query.blast_radius("lib/my_app_web/live/dashboard_live.ex", depth: 2),
        pretty: true
      )

      print_heading("Cochanges")
      IO.inspect(Query.cochanges("lib/my_app/accounts.ex", 5), pretty: true)

      print_heading("Real Reindex")
      touch_live_view!(repo_root)
      :ok = Dexterity.notify_file_changed("lib/my_app_web/live/dashboard_live.ex")
      IO.inspect(Query.find_references("MyApp.Accounts", "get_user!", 1), pretty: true)
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

  defp restart_dexterity!(repo_root, store_path, dexter_bin) do
    if Process.whereis(Dexterity.Supervisor) do
      :ok = Application.stop(:dexterity)
    end

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
        alias MyApp.{Accounts, Repo, User}

        def build_user(id) do
          Accounts.get_user!(id)
          Repo.get!(User, id)
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

  defp build_index!(dexter_bin, repo_root) do
    output = run_cmd!(dexter_bin, ["init", repo_root], repo_root)
    print_heading("Dexter Index")
    IO.puts(output)
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
