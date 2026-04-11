defmodule Mix.Tasks.Dexterity.Map do
  @moduledoc """
  Builds and prints the ranked repo map.

  Usage:
      mix dexterity.map [--active-file FILE] [--mentioned-file FILE] [--edited-file FILE]
                        [--limit N] [--token-budget N|auto]
                        [--include-clones true|false] [--repo-root PATH] [--backend MODULE]
                        [--output PATH]
  """

  use Mix.Task

  alias Dexterity
  alias Mix.Tasks.Dexterity.TaskHelpers, as: Helpers

  @shortdoc "Builds and prints the repo map"

  @impl Mix.Task
  def run(argv) do
    parsed =
      OptionParser.parse!(
        argv,
        strict: [
          repo_root: :string,
          backend: :string,
          active_file: :string,
          mentioned_file: :string,
          edited_file: :string,
          token_budget: :string,
          limit: :integer,
          include_clones: :boolean,
          output: :string
        ],
        aliases: [
          r: :repo_root,
          b: :backend,
          a: :active_file,
          m: :mentioned_file,
          e: :edited_file,
          l: :limit,
          t: :token_budget,
          o: :output
        ]
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
    include_clones = Helpers.parse_include_clones(opts)
    limit = Helpers.parse_limit(opts)
    token_budget = Helpers.parse_token_budget(opts)

    context_opts =
      [
        repo_root: repo_root,
        backend: backend,
        include_clones: include_clones,
        limit: limit,
        token_budget: token_budget,
        active_file: first_or_nil(Keyword.get_values(opts, :active_file)),
        mentioned_files: Helpers.parse_file_list(opts, :mentioned_file),
        edited_files: Helpers.parse_file_list(opts, :edited_file)
      ]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] or value == [] end)

    try do
      Application.put_env(:dexterity, :repo_root, repo_root)
      Application.put_env(:dexterity, :backend, backend)
      Helpers.ensure_started!()

      case Dexterity.get_repo_map(context_opts) do
        {:ok, rendered} ->
          output = Keyword.get(opts, :output)

          case output do
            nil ->
              Helpers.print_rendered_map(rendered)

            path ->
              File.write!(path, rendered)
              Mix.shell().info("repo map written to #{path}")
          end

        {:error, reason} ->
          Helpers.exit_with_error("map generation failed", reason)
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

  defp first_or_nil([]), do: nil
  defp first_or_nil([value | _]), do: value
end
