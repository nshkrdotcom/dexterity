defmodule Dexterity.CochangeWorkerTest do
  use ExUnit.Case

  alias Dexterity.CochangeWorker
  alias Dexterity.Store

  @db_path_template "test_cochange_worker_"

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "#{@db_path_template}#{:erlang.unique_integer([:positive])}.db"
      )

    File.rm(path)
    {:ok, conn} = Store.open(path)

    mock_cmd = fn "git", _args, _opts ->
      output = """
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

      {output, 0}
    end

    on_exit(fn ->
      Store.close(conn)
      File.rm(path)
    end)

    %{conn: conn, cmd: mock_cmd}
  end

  test "analyzes git output and upserts normalized cochange edges", %{conn: conn, cmd: cmd} do
    name = Module.concat(__MODULE__, :"CochangeWorker#{:erlang.unique_integer([:positive])}")
    root = System.tmp_dir!()

    {:ok, pid} =
      start_supervised(
        {CochangeWorker,
         repo_root: root,
         db_conn: conn,
         cmd_fn: cmd,
         enabled: true,
         interval_ms: 10_000,
         name: name}
      )

    send(pid, :analyze)

    Process.sleep(30)

    {:ok, rows} = Store.list_cochanges(conn)
    assert [{"lib/a.ex", "lib/b.ex", 3, _weight}] = rows
  end
end
