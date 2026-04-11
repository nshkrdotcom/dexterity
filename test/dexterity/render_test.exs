defmodule Dexterity.RenderTest do
  use ExUnit.Case
  alias Dexterity.Render

  test "renders files within token budget" do
    ranked_files = [{"lib/a.ex", 0.05}, {"lib/b.ex", 0.03}]

    symbols = %{
      "lib/a.ex" => [%{module: "A", function: "foo", arity: 1}]
    }

    summaries = %{"lib/a.ex" => "Summary for A"}
    clones = %{}

    budget = 40
    output = Render.render_files(ranked_files, symbols, summaries, clones, budget)

    assert String.contains?(output, "lib/a.ex")
    assert String.contains?(output, "Summary for A")
    assert String.contains?(output, "foo/1")
    refute String.contains?(output, "lib/b.ex")
  end

  test "renders clone annotation" do
    ranked_files = [{"lib/a.ex", 0.05}, {"lib/a_clone.ex", 0.04}]
    symbols = %{"lib/a.ex" => [%{module: "A", function: "foo", arity: 1}]}
    clones = %{"lib/a_clone.ex" => "lib/a.ex"}

    output = Render.render_files(ranked_files, symbols, %{}, clones, 1_000)

    assert String.contains?(output, "lib/a.ex")
    assert String.contains?(output, "[CLONE of lib/a.ex]")
  end
end
