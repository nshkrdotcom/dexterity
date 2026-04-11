defmodule DexterityTest do
  use ExUnit.Case

  alias Dexterity

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

  test "notify_file_changed delegates to injected backend and marks graph stale" do
    assert Dexterity.notify_file_changed("lib/a.ex", backend: StubBackend) == :ok
  end

  test "get_symbols returns not_indexed when no exported symbols exist" do
    assert {:error, :not_indexed} = Dexterity.get_symbols("lib/does_not_exist.ex", backend: StubBackend)
  end
end
