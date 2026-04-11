defmodule Dexterity.IndexSupervisor do
  @moduledoc """
  Supervises Dexter index lifecycle processes.
  """

  use Supervisor

  alias Dexterity.Config

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    repo_root = Keyword.get(opts, :repo_root, Config.repo_root())
    backend = Keyword.get(opts, :backend, Config.fetch(:backend))

    children = [
      {Dexterity.Indexer, [repo_root: repo_root, backend: backend]},
      {Dexterity.FileWatcher, [repo_root: repo_root, backend: backend]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
