defmodule Dexterity.MCPTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  defmodule StubBackend do
    @behaviour Dexterity.Backend

    @impl true
    def list_file_edges(_repo_root), do: {:ok, []}

    @impl true
    def list_file_nodes(_repo_root), do: {:ok, []}

    @impl true
    def list_exported_symbols(_repo_root, _file), do: {:ok, [%{module: "A", function: "foo", arity: 1, file: "lib/a.ex", line: 1}]}

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

  defp context do
    %{
      backend: StubBackend,
      repo_root: ".",
      graph_server: Dexterity.GraphServer
    }
  end

  test "initialize response contains protocol metadata" do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{"info" => "mcp-test"}
    }

    assert {:ok, %{"jsonrpc" => "2.0", "id" => 1, "result" => result}} =
             Dexterity.MCP.handle_request(request, context())

    assert result["serverName"] == "dexterity"
    assert result["protocolVersion"] == "2.0"
  end

  test "tools/list returns supported tool names" do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/list"
    }

    assert {:ok, %{"result" => %{"tools" => tools}}} = Dexterity.MCP.handle_request(request, context())
    names = Enum.map(tools, & &1["name"])

    assert "get_repo_map" in names
    assert "query_references" in names
    assert "status" in names
  end

  test "tools/call delegates to API and returns result payload" do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call",
      "params" => %{
        "name" => "get_symbols",
        "arguments" => %{
          "file" => "lib/a.ex",
          "backend" => "Elixir.Dexterity.MCPTest.StubBackend"
        }
      }
    }

    assert {:ok, %{"result" => %{"result" => symbols}}} = Dexterity.MCP.handle_request(request, context())
    assert is_list(symbols)
    assert length(symbols) == 1
  end

  test "invalid json line prints parse error" do
    output =
      capture_io(fn ->
        Dexterity.MCP.process_line("{\"jsonrpc\":", context())
      end)

    assert output =~ "\"code\":-32700"
    assert output =~ "\"error\""
  end

  test "invalid tool call returns structured error response" do
    request = %{
      "jsonrpc" => "2.0",
      "id" => 4,
      "method" => "tools/call",
      "params" => %{"name" => "missing_tool"}
    }

    assert {:ok, %{"error" => %{"code" => -32_601, "message" => "method not found"}}} =
             Dexterity.MCP.handle_request(request, context())
  end
end
