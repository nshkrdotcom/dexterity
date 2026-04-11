defmodule Dexterity.CochangeWorkerTest do
  use ExUnit.Case
  alias Dexterity.CochangeWorker
  alias Dexterity.Store
  alias Exqlite.Basic

  @db_path "test_cochange.db"

  setup do
    File.rm(@db_path)
    {:ok, conn} = Store.open(@db_path)

    on_exit(fn ->
      Store.close(conn)
      File.rm(@db_path)
    end)

    %{conn: conn}
  end

  test "analyzes git log and upserts cochanges", %{conn: conn} do
    mock_git_output = """
    ---COMMIT---
    lib/a.ex
    lib/b.ex
    README.md
    ---COMMIT---
    lib/a.ex
    lib/b.ex
    ---COMMIT---
    lib/a.ex
    lib/b.ex
    """

    mock_cmd = fn "git", _args, _opts ->
      {mock_git_output, 0}
    end

    {:ok, pid} =
      start_supervised({CochangeWorker, repo_root: ".", db_conn: conn, cmd_fn: mock_cmd})

    # Wait for the initial analyze loop
    :sys.get_state(pid)
    # The analyze message is sent asynchronously, so wait a tiny bit
    Process.sleep(50)

    # Verify DB
    {:ok, _query, result, _conn} =
      Basic.exec(conn, "SELECT file_a, file_b, frequency FROM cochanges")

    assert length(result.rows) == 1
    [[file_a, file_b, freq]] = result.rows

    assert file_a == "lib/a.ex"
    assert file_b == "lib/b.ex"
    assert freq == 3
  end
end
