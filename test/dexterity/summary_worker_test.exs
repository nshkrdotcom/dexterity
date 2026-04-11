defmodule Dexterity.SummaryWorkerTest do
  use ExUnit.Case

  alias Dexterity.SummaryWorker
  alias Dexterity.Store

  setup do
    path = Path.join(System.tmp_dir!(), "test_summary_worker_#{:erlang.unique_integer([:positive])}.db")
    {:ok, conn} = Store.open(path)

    mock_llm = fn _prompt -> {:ok, "Mock summary under 80 chars."} end
    name = Module.concat(__MODULE__, :"SummaryWorker#{:erlang.unique_integer([:positive])}")

    on_exit(fn ->
      Store.close(conn)
      File.rm(path)
    end)

    %{conn: conn, name: name, mock_llm: mock_llm}
  end

  test "summarizes and caches semantic text", %{conn: conn, name: name, mock_llm: mock_llm} do
    {:ok, pid} =
      start_supervised(
        {SummaryWorker,
         [
           db_conn: conn,
           llm_fn: mock_llm,
           enabled: true,
           name: name
         ]}
      )

    SummaryWorker.summarize(pid, "lib/my_module.ex", "MyModule", 12_345, "def my_func()")
    Process.sleep(20)

    assert {:ok, result} = Store.get_summary(conn, "lib/my_module.ex", "MyModule")
    assert {"Mock summary under 80 chars.", 12_345} = result
  end
end
