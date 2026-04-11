defmodule Dexterity.ApplicationControl do
  @moduledoc false

  require Logger

  @spec stop_quietly(atom()) :: :ok | {:error, term()}
  def stop_quietly(app) when is_atom(app) do
    previous_level = Logger.level()

    try do
      Logger.configure(level: :warning)
      Application.stop(app)
    after
      Logger.configure(level: previous_level)
    end
  end
end
