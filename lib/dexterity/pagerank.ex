defmodule Dexterity.PageRank do
  @moduledoc """
  Deterministic personalized PageRank implementation.
  """

  alias Dexterity.Config

  @spec compute(
          %{String.t() => %{String.t() => float()}},
          [String.t()],
          [String.t()],
          keyword()
        ) :: %{String.t() => float()}
  def compute(graph, context_files, all_files, opts \\ []) do
    if all_files == [] do
      %{}
    else
      damping = Keyword.get(opts, :damping, Config.fetch(:pagerank_damping))
      iterations = Keyword.get(opts, :iterations, Config.fetch(:pagerank_iterations))

      uniform_baseline =
        Keyword.get(opts, :uniform_baseline, Config.fetch(:pagerank_uniform_baseline))

      context_boost = Keyword.get(opts, :context_boost, Config.fetch(:pagerank_context_boost))

      context_normalized = Enum.uniq(context_files)
      n = length(all_files)
      uniform = 1.0 / n
      base_scores = Map.new(all_files, &{&1, uniform})

      teleport =
        context_vector(all_files, context_normalized, n, uniform_baseline, context_boost)
        |> normalize()

      out_sums =
        Map.new(all_files, fn file -> {file, outgoing_sum(Map.get(graph, file, %{}))} end)

      Enum.reduce(1..iterations, base_scores, fn _i, ranks ->
        dangling = dangling_mass(ranks, out_sums, graph)
        propagated = propagate(ranks, graph, out_sums)
        combine(propagated, teleport, dangling, damping, all_files)
      end)
    end
  end

  defp context_vector(all_files, context_files, n, uniform_baseline, context_boost) do
    context_set = MapSet.new(context_files)
    base = uniform_baseline / n

    if context_files == [] do
      Map.new(all_files, fn file -> {file, base} end)
    else
      context_share = context_boost / length(context_files)

      Map.new(all_files, fn file ->
        extra =
          if MapSet.member?(context_set, file) do
            context_share
          else
            0.0
          end

        {file, base + extra}
      end)
    end
  end

  defp combine(propagated, teleport, dangling, damping, all_files) do
    teleport_mass = 1.0 - damping
    d_dangling = damping * dangling

    Enum.reduce(all_files, %{}, fn file, acc ->
      score =
        damping * propagated[file] + teleport_mass * teleport[file] + d_dangling * teleport[file]

      Map.put(acc, file, score)
    end)
  end

  defp propagate(ranks, graph, out_sums) do
    Enum.reduce(ranks, Map.new(Map.keys(ranks), fn k -> {k, 0.0} end), fn {from, rank}, acc ->
      edges = Map.get(graph, from, %{})
      denominator = Map.get(out_sums, from, 0.0)

      if denominator <= 0 do
        acc
      else
        Enum.reduce(edges, acc, fn {to, weight}, next ->
          share = rank * weight / denominator
          Map.update!(next, to, &(&1 + share))
        end)
      end
    end)
  end

  defp dangling_mass(ranks, out_sums, graph) do
    Enum.reduce(ranks, 0.0, fn {file, score}, total ->
      if Map.get(graph, file, %{}) == %{} or Map.get(out_sums, file, 0.0) <= 0 do
        total + score
      else
        total
      end
    end)
  end

  defp outgoing_sum(map) do
    Enum.sum(Map.values(map))
  end

  defp normalize(vector) when is_map(vector) do
    total = Enum.sum(Map.values(vector))

    if total <= 0 do
      vector
    else
      Map.new(vector, fn {k, v} -> {k, v / total} end)
    end
  end
end
