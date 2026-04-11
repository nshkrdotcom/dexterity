defmodule Dexterity.SummaryWorkerTest do
  use ExUnit.Case
  alias Dexterity.Store
  alias Dexterity.SummaryWorker
  alias Exqlite.Basic

  @db_path "test_summary.db"

  setup do
    File.rm(@db_path)
    {:ok, conn} = Store.open(@db_path)

    on_exit(fn ->
      Store.close(conn)
      File.rm(@db_path)
    end)

    %{conn: conn}
  end

  test "fetches and caches summary", %{conn: conn} do
    mock_llm = fn _prompt -> {:ok, "Mock summary under 80 chars."} end

    {:ok, pid} =
      start_supervised(
        {SummaryWorker,
         db_conn: conn, llm_fn: mock_llm}
      )

    SummaryWorker.summarize(pid, "lib/my_module.ex", "MyModule", 12_345, "def my_func()")

    # Wait for cast to be processed
    :sys.get_state(pid)

    {:ok, _query, result, _conn} =
      Basic.exec(conn, "SELECT summary, file_mtime FROM semantic_summaries")

    assert length(result.rows) == 1

    [[summary, mtime]] = result.rows
    assert summary == "Mock summary under 80 chars."
    assert mtime == 12_345
  end
end
