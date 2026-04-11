defmodule Dexterity.GraphServerTest do
  use ExUnit.Case
  alias Dexterity.GraphServer

  @repo_root System.tmp_dir!()
  @db_path Path.join(@repo_root, ".dexter.db")

  setup do
    File.rm(@db_path)
    {:ok, conn} = Exqlite.Basic.open(@db_path)

    Exqlite.Basic.exec(
      conn,
      "CREATE TABLE definitions (module TEXT, function TEXT, arity INTEGER, file TEXT, line INTEGER)"
    )

    Exqlite.Basic.exec(
      conn,
      "CREATE TABLE \"references\" (caller_file TEXT, target_module TEXT, target_function TEXT, target_arity INTEGER)"
    )

    # Insert mock data to create edge lib/caller.ex -> lib/my_module.ex
    Exqlite.Basic.exec(
      conn,
      "INSERT INTO definitions VALUES ('MyModule', 'my_func', 1, 'lib/my_module.ex', 10)"
    )

    Exqlite.Basic.exec(
      conn,
      "INSERT INTO \"references\" VALUES ('lib/caller.ex', 'MyModule', 'my_func', 1)"
    )

    Exqlite.Basic.close(conn)

    {:ok, pid} = start_supervised({GraphServer, repo_root: @repo_root})

    # Wait a bit for initial graph build
    :sys.get_state(pid)

    on_exit(fn -> File.rm(@db_path) end)
    %{server: pid}
  end

  test "get_repo_map computes ranks correctly", %{server: pid} do
    {:ok, ranks} = GraphServer.get_repo_map(pid, [])

    assert map_size(ranks) == 2
    assert Map.has_key?(ranks, "lib/caller.ex")
    assert Map.has_key?(ranks, "lib/my_module.ex")
  end

  test "mark_stale forces a rebuild", %{server: pid} do
    GraphServer.mark_stale(pid)

    # Wait for the cast to process
    state = :sys.get_state(pid)
    assert state.stale == true

    # get_repo_map triggers rebuild
    {:ok, _ranks} = GraphServer.get_repo_map(pid, [])

    state = :sys.get_state(pid)
    assert state.stale == false
  end
end
