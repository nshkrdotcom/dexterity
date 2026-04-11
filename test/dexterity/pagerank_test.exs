defmodule Dexterity.PageRankTest do
  use ExUnit.Case
  alias Dexterity.PageRank

  test "computes basic pagerank without context" do
    # Simple graph: A -> B, B -> C, C -> A
    graph = %{
      "A" => %{"B" => 1.0},
      "B" => %{"C" => 1.0},
      "C" => %{"A" => 1.0}
    }

    all_files = ["A", "B", "C"]

    ranks = PageRank.compute(graph, [], all_files)

    # In a symmetric ring without context, all should have rank ~1/3
    assert_in_delta ranks["A"], 1 / 3, 0.01
    assert_in_delta ranks["B"], 1 / 3, 0.01
    assert_in_delta ranks["C"], 1 / 3, 0.01

    # Sum should be 1.0
    sum = ranks["A"] + ranks["B"] + ranks["C"]
    assert_in_delta sum, 1.0, 0.0001
  end

  test "context boosts specific files" do
    # Same graph, but boost A
    graph = %{
      "A" => %{"B" => 1.0},
      "B" => %{"C" => 1.0},
      "C" => %{"A" => 1.0}
    }

    all_files = ["A", "B", "C"]

    ranks = PageRank.compute(graph, ["A"], all_files)

    # A should have the highest rank now due to the personalization vector
    # But because A links to B, B also gets a lot of rank.
    # C is furthest, so C gets the least from the teleport.
    assert ranks["A"] > 0.33

    # Sum should remain 1.0
    sum = ranks["A"] + ranks["B"] + ranks["C"]
    assert_in_delta sum, 1.0, 0.0001
  end

  test "handles dangling nodes" do
    # A -> B, B -> C, C has no outgoing edges
    graph = %{
      "A" => %{"B" => 1.0},
      "B" => %{"C" => 1.0}
    }

    all_files = ["A", "B", "C"]

    ranks = PageRank.compute(graph, [], all_files)

    # Sum should be 1.0
    sum = ranks["A"] + ranks["B"] + ranks["C"]
    assert_in_delta sum, 1.0, 0.0001

    # C should have high rank as rank accumulates there before teleporting
    assert ranks["C"] > ranks["A"]
  end

  test "empty graph" do
    assert PageRank.compute(%{}, [], []) == %{}
  end
end
