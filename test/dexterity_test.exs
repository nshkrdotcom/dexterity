defmodule DexterityTest do
  use ExUnit.Case
  alias Dexterity

  test "notify_file_changed returns ok" do
    # Simply test it calls the backend properly without crashing
    # Requires Dexterity.GraphServer to be running
    assert Dexterity.notify_file_changed("lib/a.ex") == :ok
  end
end
