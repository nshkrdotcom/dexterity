test_store_path =
  Path.join(
    System.tmp_dir!(),
    "dexterity-test-store-#{System.system_time(:microsecond)}.db"
  )

Application.put_env(:dexterity, :store_path, test_store_path)

ExUnit.start()
