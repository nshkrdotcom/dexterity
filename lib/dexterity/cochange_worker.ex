defmodule Dexterity.CochangeWorker do
  @moduledoc """
  Background worker that analyzes git history to establish temporal coupling edges.
  """
  use GenServer

  alias Exqlite.Basic

  @default_limit 500
  @default_min_freq 3
  # 30 minutes
  @interval 30 * 60 * 1000

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    repo_root = Keyword.fetch!(opts, :repo_root)
    db_conn = Keyword.fetch!(opts, :db_conn)
    cmd_fn = Keyword.get(opts, :cmd_fn, &System.cmd/3)

    GenServer.start_link(
      __MODULE__,
      %{
        repo_root: repo_root,
        db_conn: db_conn,
        cmd_fn: cmd_fn
      },
      name: name
    )
  end

  @impl true
  def init(state) do
    send(self(), :analyze)
    {:ok, state}
  end

  @impl true
  def handle_info(:analyze, state) do
    analyze_cochanges(state.repo_root, state.db_conn, state.cmd_fn)
    Process.send_after(self(), :analyze, @interval)
    {:noreply, state}
  end

  # credo:disable-for-next-line Credo.Check.Refactor.Nesting
  defp analyze_cochanges(repo_root, db_conn, cmd_fn) do
    case cmd_fn.(
           "git",
           ["log", "--name-only", "--format=---COMMIT---", "-n", to_string(@default_limit)],
           cd: repo_root
         ) do
      {output, 0} ->
        now = System.os_time(:second)

        output
        |> String.split("---COMMIT---", trim: true)
        |> Enum.flat_map(&parse_commit_block/1)
        |> Enum.frequencies()
        |> Enum.filter(fn {_pair, count} -> count >= @default_min_freq end)
        |> Enum.each(fn {{a, b}, count} ->
          weight = :math.log(count) * 2.0
          upsert_cochange(db_conn, a, b, count, weight, now)
        end)

      _ ->
        # Git command failed or not a git repo
        :ok
    end
  end

  defp parse_commit_block(commit_block) do
    files =
      commit_block
      |> String.split("\n", trim: true)
      |> Enum.filter(&elixir_file?/1)

    for a <- files, b <- files, a < b, do: {a, b}
  end

  defp elixir_file?(file) do
    String.ends_with?(file, ".ex") or String.ends_with?(file, ".exs")
  end

  defp upsert_cochange(conn, a, b, count, weight, now) do
    sql = """
    INSERT INTO cochanges (file_a, file_b, frequency, weight, updated_at)
    VALUES (?1, ?2, ?3, ?4, ?5)
    ON CONFLICT(file_a, file_b) DO UPDATE SET
      frequency = excluded.frequency,
      weight = excluded.weight,
      updated_at = excluded.updated_at
    """

    {:ok, _, _, _} = Basic.exec(conn, sql, [a, b, count, weight, now])
  end
end
