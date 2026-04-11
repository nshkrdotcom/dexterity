defmodule Dexterity.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Children will be added here as implementation proceeds
    ]

    opts = [strategy: :one_for_one, name: Dexterity.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
