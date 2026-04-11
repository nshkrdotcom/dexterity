defmodule Dexterity.StoreServer do
  @moduledoc """
  Owns a single Dexterity metadata SQLite connection.
  """

  use GenServer

  alias Dexterity.Config
  alias Dexterity.Store

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, [], name: name)
  end

  def conn(server \\ __MODULE__) do
    GenServer.call(server, :get_conn)
  end

  @impl true
  def init(_opts) do
    case Store.open(Config.store_path()) do
      {:ok, conn} -> {:ok, conn}
      error -> {:stop, error}
    end
  end

  @impl true
  def terminate(_reason, conn) do
    Store.close(conn)
  end

  @impl true
  def handle_call(:get_conn, _from, conn) do
    {:reply, conn, conn}
  end
end
