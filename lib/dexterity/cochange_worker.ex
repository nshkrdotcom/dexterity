defmodule Dexterity.CochangeWorker do
  @moduledoc """
  Background worker that computes git temporal-coupling edges.
  """

  use GenServer

  alias Dexterity.Config
  alias Dexterity.Store
  alias Dexterity.StoreServer

  @elixir_extensions [".ex", ".exs"]

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    repo_root = Keyword.fetch!(opts, :repo_root)
    db_conn =
      case Keyword.fetch(opts, :db_conn) do
        {:ok, value} -> value
        :error -> StoreServer.conn()
      end

    state = %{
      repo_root: repo_root,
      db_conn: db_conn,
      cmd_fn: Keyword.get(opts, :cmd_fn, &System.cmd/3),
      interval_ms: Keyword.get(opts, :interval_ms, Config.cochange_interval_ms()),
      min_freq: Keyword.get(opts, :min_frequency, Config.fetch(:cochange_min_frequency)),
      max_commits: Keyword.get(opts, :max_commits, Config.fetch(:cochange_commit_depth)),
      enabled: Keyword.get(opts, :enabled, Config.cochange_enabled?())
    }

    GenServer.start_link(__MODULE__, state, name: name)
  end

  @impl true
  def init(state) do
    if state.enabled do
      send(self(), :analyze)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:analyze, state) do
    analyze(state)

    if state.enabled do
      Process.send_after(self(), :analyze, state.interval_ms)
    end

    {:noreply, state}
  end

  defp analyze(state) do
    with {output, 0} <- run_cmd(state),
         {:ok, parsed} <- parse_cochange_output(output, state.min_freq) do
      now = System.os_time(:second)

      Enum.each(parsed, fn {{file_a, file_b}, count} ->
        weight = :math.log(count) * 2.0
        Store.upsert_cochange(state.db_conn, file_a, file_b, count, weight, now)
      end)
    else
      _ -> :ok
    end
  end

  defp run_cmd(state) do
    state.cmd_fn.(
      "git",
      [
        "log",
        "--name-only",
        "--pretty=format:---COMMIT---",
        "-n",
        to_string(state.max_commits)
      ],
      cd: state.repo_root
    )
  end

  defp parse_cochange_output(output, min_frequency) do
    parsed =
      output
      |> String.split("---COMMIT---", trim: true)
      |> Enum.map(&extract_files/1)
      |> Enum.map(&ordered_pairs/1)
      |> List.flatten()
      |> Enum.frequencies()
      |> Enum.filter(fn {_pair, count} -> count >= min_frequency end)

    {:ok, parsed}
  end

  defp extract_files(block) do
    block
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&ex_file?/1)
    |> Enum.uniq()
  end

  defp ordered_pairs(files) when length(files) < 2, do: []
  defp ordered_pairs(files) do
    for a <- files, b <- files, a < b do
      {a, b}
    end
  end

  defp ex_file?(path), do: Path.extname(path) in @elixir_extensions
end
