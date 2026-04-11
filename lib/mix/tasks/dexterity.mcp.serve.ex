defmodule Mix.Tasks.Dexterity.Mcp.Serve do
  @moduledoc """
  Runs Dexterity MCP over stdio as JSON-RPC.

  Usage:
      mix dexterity.mcp.serve [--repo-root PATH] [--backend MODULE]
  """

  use Mix.Task

  alias Dexterity.Config
  alias Mix.Tasks.Dexterity.TaskHelpers, as: Helpers

  @shortdoc "Starts MCP server over stdio"

  @impl Mix.Task
  @spec run([String.t()]) :: no_return() | :ok
  def run(argv) do
    parsed =
      OptionParser.parse!(argv,
        strict: [repo_root: :string, backend: :string],
        aliases: [r: :repo_root, b: :backend]
      )

    opts = elem(parsed, 0)
    args = elem(parsed, 1)

    if args != [] do
      Helpers.exit_with_error("unexpected positional args", args)
    end

    previous = [
      repo_root: Application.get_env(:dexterity, :repo_root),
      backend: Application.get_env(:dexterity, :backend)
    ]

    repo_root = Helpers.parse_repo_root(opts)
    backend = Helpers.parse_backend(opts)

    try do
      Application.put_env(:dexterity, :repo_root, repo_root)
      Application.put_env(:dexterity, :backend, backend)
      Helpers.ensure_started!()

      if !Config.fetch(:mcp_enabled) do
        Mix.shell().info(
          "warning: mcp_enabled is false; proceeding because server is explicitly launched"
        )
      end

      Dexterity.MCP.serve(repo_root: repo_root, backend: backend)
    after
      Enum.each(previous, fn {key, value} ->
        if is_nil(value) do
          Application.delete_env(:dexterity, key)
        else
          Application.put_env(:dexterity, key, value)
        end
      end)
    end
  end
end
