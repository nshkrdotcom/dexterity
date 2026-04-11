defmodule Mix.Tasks.Dexterity.Index do
  @moduledoc """
  Triggers a Dexter index refresh for the target repo root.

  Usage:
      mix dexterity.index [--repo-root PATH] [--backend MODULE]
  """

  use Mix.Task

  alias Mix.Tasks.Dexterity.TaskHelpers, as: Helpers

  @shortdoc "Refreshes the Dexter index for a repository"

  @impl Mix.Task
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

    repo_root = Helpers.parse_repo_root(opts)
    backend = Helpers.parse_backend(opts)
    Application.put_env(:dexterity, :repo_root, repo_root)
    Application.put_env(:dexterity, :backend, backend)
    Helpers.ensure_started!()

    case backend.cold_index(repo_root, []) do
      :ok ->
        Mix.shell().info("index refreshed for #{repo_root}")

      {:error, reason} ->
        Helpers.exit_with_error("index refresh failed", reason)
    end
  end
end
