defmodule Dexterity do
  @moduledoc """
  Dexterity: Authoritative, ranked, token-budgeted codebase context for Elixir agents.
  """

  alias Dexterity.Backend.Dexter, as: Backend
  alias Dexterity.GraphServer
  alias Dexterity.Render

  @type context_opts :: [
          active_file: String.t() | nil,
          mentioned_files: [String.t()],
          edited_files: [String.t()],
          token_budget: pos_integer() | :auto,
          include_clones: boolean(),
          min_rank: float()
        ]

  @default_budget 8192

  @doc """
  Returns a token-bounded Markdown string representing the most relevant parts of the codebase.
  """
  @spec get_repo_map(context_opts()) :: {:ok, String.t()} | {:error, term()}
  def get_repo_map(opts \\ []) do
    active_file = Keyword.get(opts, :active_file)
    mentioned_files = Keyword.get(opts, :mentioned_files, [])
    edited_files = Keyword.get(opts, :edited_files, [])
    budget = Keyword.get(opts, :token_budget, @default_budget)
    budget = if budget == :auto, do: @default_budget, else: budget

    context_files =
      ([active_file | mentioned_files] ++ edited_files)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case GraphServer.get_repo_map(Dexterity.GraphServer, context_files) do
      {:ok, ranks} ->
        ranked_files =
          ranks
          |> Enum.sort_by(fn {_file, score} -> score end, :desc)

        # In a full implementation, we would query the database here to get symbols,
        # summaries, and clones. For now, we stub them.
        symbols = %{}
        summaries = %{}
        clones = %{}

        output = Render.render_files(ranked_files, symbols, summaries, clones, budget)
        {:ok, output}

      error ->
        error
    end
  end

  @doc """
  Returns exported symbols for a specific file.
  """
  @spec get_symbols(String.t()) :: {:ok, [map()]} | {:error, :not_indexed}
  def get_symbols(file) do
    # Assuming project root is current working directory for the API
    symbols = Backend.list_exported_symbols(File.cwd!(), file)

    if symbols == [] do
      {:error, :not_indexed}
    else
      {:ok, symbols}
    end
  end

  @doc """
  Force-triggers reindex of a specific file.
  """
  @spec notify_file_changed(String.t()) :: :ok
  def notify_file_changed(file) do
    Backend.reindex_file(file)
    GraphServer.mark_stale(Dexterity.GraphServer)
    :ok
  end
end
