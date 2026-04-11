defmodule Dexterity.StoreTest do
  use ExUnit.Case
  alias Dexterity.Store

  @db_path "test_dexterity.db"

  setup do
    File.rm(@db_path)
    on_exit(fn -> File.rm(@db_path) end)
    :ok
  end

  test "opens database and creates schema" do
    assert {:ok, conn} = Store.open(@db_path)
    assert File.exists?(@db_path)

    # Verify a table exists by inserting into it
    insert_sql = """
    INSERT INTO index_meta (key, value) VALUES ('test_key', 'test_value')
    """

    assert {:ok, _, _, _} = Exqlite.Basic.exec(conn, insert_sql)

    assert :ok = Store.close(conn)
  end
end
