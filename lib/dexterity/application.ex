defmodule Dexterity.Application do
  @moduledoc false
  use Application

  alias Dexterity.Config
  alias Dexterity.StoreServer

  @impl true
  def start(_type, _args) do
    children = [
      {StoreServer, []},
      {Dexterity.IndexSupervisor,
       [repo_root: Config.repo_root(), backend: Config.fetch(:backend)]},
      {Dexterity.GraphServer, [repo_root: Config.repo_root(), backend: Config.fetch(:backend)]},
      {Dexterity.SymbolGraphServer,
       [repo_root: Config.repo_root(), backend: Config.fetch(:backend)]},
      {Dexterity.CochangeWorker,
       [repo_root: Config.repo_root(), interval_ms: Config.cochange_interval_ms()]},
      {Dexterity.SummaryWorker, [enabled: Config.fetch(:summary_enabled)]}
    ]

    opts = [strategy: :one_for_one, name: Dexterity.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
