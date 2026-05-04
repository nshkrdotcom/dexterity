defmodule Dexterity.GovernedAuthorityTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Dexterity.GovernedAuthority
  alias Mix.Tasks.Dexterity.Index

  setup do
    repo_root =
      Path.join(
        System.tmp_dir!(),
        "dexterity-governed-authority-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(repo_root)

    previous = %{
      repo_root: Application.get_env(:dexterity, :repo_root),
      backend: Application.get_env(:dexterity, :backend),
      dexter_bin: Application.get_env(:dexterity, :dexter_bin),
      dexter_db: Application.get_env(:dexterity, :dexter_db),
      store_path: Application.get_env(:dexterity, :store_path),
      mcp_enabled: Application.get_env(:dexterity, :mcp_enabled)
    }

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> restore_env(key, value) end)
      File.rm_rf!(repo_root)
    end)

    %{repo_root: repo_root}
  end

  test "materialization ignores ambient app config", %{repo_root: repo_root} do
    Application.put_env(:dexterity, :repo_root, "/ambient/repo")
    Application.put_env(:dexterity, :backend, Dexterity.Backend.Dexter)
    Application.put_env(:dexterity, :dexter_bin, "/ambient/dexter")
    Application.put_env(:dexterity, :mcp_enabled, false)

    assert {:ok, opts} =
             GovernedAuthority.materialize_opts(governed_authority: authority(repo_root))

    assert opts[:repo_root] == repo_root
    assert opts[:backend] == Dexterity.Backend.Mock
    assert opts[:dexter_bin] == "/authority/dexter"
    assert opts[:mcp_enabled] == true
    refute inspect(opts) =~ "/ambient"
  end

  test "direct config is rejected beside governed authority", %{repo_root: repo_root} do
    authority = authority(repo_root)

    direct_fields = [
      repo_root: repo_root,
      backend: Dexterity.Backend.Dexter,
      dexter_bin: "/direct/dexter",
      dexter_db: ".direct.db",
      store_path: "/direct/store.db",
      mcp_enabled: false,
      command_env: [{"TOKEN", "direct"}],
      tool_config: %{token: "direct"}
    ]

    for {field, value} <- direct_fields do
      assert {:error, {:direct_governed_config, fields}} =
               GovernedAuthority.materialize_opts([
                 {:governed_authority, authority},
                 {field, value}
               ])

      assert field in fields
    end
  end

  test "public API rejects direct routing beside governed authority", %{repo_root: repo_root} do
    error =
      assert_raise ArgumentError, fn ->
        Dexterity.get_symbols(
          "lib/a.ex",
          governed_authority: authority(repo_root),
          repo_root: repo_root
        )
      end

    assert String.contains?(error.message, "direct_governed_config")
  end

  test "redaction removes authority selected command material", %{repo_root: repo_root} do
    assert {:ok, opts} =
             GovernedAuthority.materialize_opts(governed_authority: authority(repo_root))

    output =
      GovernedAuthority.redact(
        "using /authority/dexter with governed-secret-value",
        opts[:redaction_values]
      )

    refute output =~ "/authority/dexter"
    refute output =~ "governed-secret-value"
    assert output =~ "[REDACTED]"
  end

  test "mcp context uses only governed authority values", %{repo_root: repo_root} do
    Application.put_env(:dexterity, :repo_root, "/ambient/repo")
    Application.put_env(:dexterity, :backend, Dexterity.Backend.Dexter)

    assert {:ok, context} =
             Dexterity.MCP.runtime_context(governed_authority: authority(repo_root))

    assert context.repo_root == repo_root
    assert context.backend == Dexterity.Backend.Mock
    refute inspect(context) =~ "/ambient"
  end

  test "governed mcp rejects per-request routing overrides", %{repo_root: repo_root} do
    assert {:ok, context} =
             Dexterity.MCP.runtime_context(governed_authority: authority(repo_root))

    request = %{
      "jsonrpc" => "2.0",
      "id" => 7,
      "method" => "tools/call",
      "params" => %{
        "name" => "get_symbols",
        "arguments" => %{
          "file" => "lib/a.ex",
          "backend" => "Elixir.Dexterity.Backend.Dexter"
        }
      }
    }

    assert {:ok, %{"error" => %{"message" => "invalid params", "data" => data}}} =
             Dexterity.MCP.handle_request(request, context)

    assert String.contains?(data, "direct MCP config cannot accompany governed authority")
  end

  test "index task rejects direct flags beside governed authority", %{repo_root: repo_root} do
    error =
      assert_raise Mix.Error, fn ->
        Index.run(governed_index_args(repo_root) ++ ["--repo-root", repo_root])
      end

    assert String.contains?(error.message, "direct config cannot accompany governed authority")
  end

  test "index task accepts governed flags without ambient config", %{repo_root: repo_root} do
    Application.put_env(:dexterity, :repo_root, "/ambient/repo")
    Application.put_env(:dexterity, :backend, Dexterity.Backend.Dexter)
    Application.put_env(:dexterity, :dexter_bin, "/ambient/dexter")

    output =
      capture_io(fn ->
        Index.run(governed_index_args(repo_root))
      end)

    assert output =~ "index refreshed for #{repo_root}"
  end

  defp authority(repo_root) do
    %{
      authority_ref: "auth-dexterity",
      tool_ref: "dexterity.cli",
      operation_ref: "index",
      repo_ref: "repo-dexterity",
      backend_ref: "mock",
      command_ref: "dexter-command",
      credential_ref: "credential-dexterity",
      repo_root: repo_root,
      dexter_bin: "/authority/dexter",
      dexter_db: ".governed-dexter.db",
      store_path: Path.join(repo_root, ".dexterity/governed.db"),
      mcp_enabled: true,
      credential_value: "governed-secret-value"
    }
  end

  defp governed_index_args(repo_root) do
    [
      "--governed-authority-ref",
      "auth-dexterity",
      "--governed-tool-ref",
      "dexterity.cli",
      "--governed-operation-ref",
      "index",
      "--governed-repo-ref",
      "repo-dexterity",
      "--governed-backend-ref",
      "mock",
      "--governed-command-ref",
      "dexter-command",
      "--governed-credential-ref",
      "credential-dexterity",
      "--governed-repo-root",
      repo_root,
      "--governed-dexter-bin",
      "/authority/dexter",
      "--governed-dexter-db",
      ".governed-dexter.db",
      "--governed-store-path",
      Path.join(repo_root, ".dexterity/governed.db"),
      "--governed-mcp-enabled",
      "true"
    ]
  end

  defp restore_env(key, nil), do: Application.delete_env(:dexterity, key)
  defp restore_env(key, value), do: Application.put_env(:dexterity, key, value)
end
