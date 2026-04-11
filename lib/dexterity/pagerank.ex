defmodule Dexterity.PageRank do
  @moduledoc """
  Calculates Personalized PageRank for the codebase graph.
  """

  @damping 0.85
  @iterations 20
  @uniform_baseline 0.70
  @context_boost 0.30

  @doc """
  Computes the PageRank of files given a weighted adjacency map.

  `graph` is expected to be a map of `%{source_file => %{target_file => weight}}`.
  """
  def compute(graph, context_files, all_files) do
    n = length(all_files)

    if n == 0 do
      %{}
    else
      uniform = 1.0 / n

      # Personalization vector (teleport probabilities)
      pv =
        Map.new(all_files, fn file ->
          base = uniform * @uniform_baseline

          boost =
            if file in context_files do
              @context_boost / max(length(context_files), 1)
            else
              0.0
            end

          {file, base + boost}
        end)

      # Ensure PV sums to 1.0 (might slightly deviate due to floats, but close enough)
      pv_sum = Enum.sum(Map.values(pv))
      pv = Map.new(pv, fn {k, v} -> {k, v / pv_sum} end)

      # Build normalized transition matrix (out-degrees)
      # For a node, the sum of outgoing edge weights
      out_sums =
        Map.new(all_files, fn file ->
          edges = Map.get(graph, file, %{})
          {file, Enum.sum(Map.values(edges))}
        end)

      # Power iteration
      initial = Map.new(all_files, fn file -> {file, uniform} end)

      Enum.reduce(1..@iterations, initial, fn _, current_rank ->
        # Calculate dangling rank sum (nodes with no out-edges)
        dangling_sum =
          Enum.reduce(all_files, 0.0, fn file, sum ->
            if out_sums[file] == 0.0 do
              sum + current_rank[file]
            else
              sum
            end
          end)

        # Propagate rank through edges
        propagated = propagate_ranks(all_files, graph, out_sums, current_rank)

        # Add teleportation and dangling rank back
        # rank(v) = damping * propagated(v) + (1 - damping) * pv(v) + damping * dangling_sum * pv(v)
        Map.new(all_files, fn file ->
          base_rank = @damping * propagated[file]
          teleport = (1.0 - @damping) * pv[file]
          dangling = @damping * dangling_sum * pv[file]
          {file, base_rank + teleport + dangling}
        end)
      end)
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.Nesting
  defp propagate_ranks(all_files, graph, out_sums, current_rank) do
    Enum.reduce(all_files, Map.new(all_files, fn f -> {f, 0.0} end), fn u, new_rank ->
      edges = Map.get(graph, u, %{})
      out_sum_u = out_sums[u]

      if out_sum_u > 0.0 do
        Enum.reduce(edges, new_rank, fn {v, weight}, acc ->
          # rank share is proportional to edge weight
          share = current_rank[u] * (weight / out_sum_u)
          Map.update!(acc, v, &(&1 + share))
        end)
      else
        new_rank
      end
    end)
  end
end
