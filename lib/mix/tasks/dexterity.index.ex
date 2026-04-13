defmodule Mix.Tasks.Dexterity.Index do
  @moduledoc """
  Triggers a Dexter index refresh for the target repo root.

  Usage:
      mix dexterity.index [--repo-root PATH] [--backend MODULE] [--dexter-bin PATH]
  """

  use Mix.Task

  alias Mix.Tasks.Dexterity.TaskHelpers, as: Helpers

  @shortdoc "Refreshes the Dexter index for a repository"

  @impl Mix.Task
  def run(argv) do
    parsed =
      OptionParser.parse!(argv,
        strict: [repo_root: :string, backend: :string, dexter_bin: :string],
        aliases: [r: :repo_root, b: :backend]
      )

    opts = elem(parsed, 0)
    args = elem(parsed, 1)

    if args != [] do
      Helpers.exit_with_error("unexpected positional args", args)
    end

    repo_root = Helpers.parse_repo_root(opts)
    backend = Helpers.parse_backend(opts)
    dexter_bin = Helpers.parse_dexter_bin(opts)

    previous = [
      repo_root: Application.get_env(:dexterity, :repo_root),
      backend: Application.get_env(:dexterity, :backend),
      dexter_bin: Application.get_env(:dexterity, :dexter_bin)
    ]

    try do
      Application.put_env(:dexterity, :repo_root, repo_root)
      Application.put_env(:dexterity, :backend, backend)
      Application.put_env(:dexterity, :dexter_bin, dexter_bin)

      case refresh_index(backend, repo_root) do
        :ok ->
          Mix.shell().info("index refreshed for #{repo_root}")

        {:error, reason} ->
          Helpers.exit_with_error("index refresh failed", reason)
      end
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

  defp refresh_index(backend, repo_root) do
    case backend.index_status(repo_root) do
      {:ok, :missing} ->
        backend.cold_index(repo_root, [])

      {:ok, status} when status in [:ready, :stale] ->
        backend.reindex_file(".", repo_root: repo_root)

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_index_status, other}}
    end
  end
end
