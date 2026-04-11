defmodule Mix.Tasks.Dexterity.Status do
  @moduledoc """
  Prints a deterministic runtime status snapshot.

  Usage:
      mix dexterity.status [--repo-root PATH] [--backend MODULE]
  """

  use Mix.Task

  alias Dexterity
  alias Mix.Tasks.Dexterity.TaskHelpers, as: Helpers

  @shortdoc "Prints Dexterity runtime status"

  @impl Mix.Task
  def run(argv) do
    parsed = OptionParser.parse!(argv, strict: [repo_root: :string, backend: :string], aliases: [r: :repo_root, b: :backend])

    opts = elem(parsed, 0)
    args = elem(parsed, 1)

    if args != [] do
      Helpers.exit_with_error("unexpected positional args", args)
    end

    repo_root = Helpers.parse_repo_root(opts)
    backend = Helpers.parse_backend(opts)

    previous = [
      repo_root: Application.get_env(:dexterity, :repo_root),
      backend: Application.get_env(:dexterity, :backend)
    ]

    try do
      Application.put_env(:dexterity, :repo_root, repo_root)
      Application.put_env(:dexterity, :backend, backend)
      Helpers.ensure_started!()

      case Dexterity.status() do
        {:ok, snapshot} ->
          print_status(snapshot)

        {:error, reason} ->
          Helpers.exit_with_error("status unavailable", reason)
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

  defp print_status(snapshot) do
    snapshot
    |> Enum.each(fn {key, value} ->
      Mix.shell().info("#{key}: #{inspect(value)}")
    end)
  end
end
