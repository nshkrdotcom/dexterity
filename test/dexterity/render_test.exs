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

  test "renders metadata annotations and suppresses symbol body for clone blocks" do
    ranked_files = [
      {"lib/support/data_case.ex", 0.06},
      {"lib/notifications/email.ex", 0.05},
      {"lib/notifications/email_copy.ex", 0.04}
    ]

    symbols = %{
      "lib/notifications/email.ex" => [%{module: "MyApp.Notifications.Email", function: "deliver", arity: 1}],
      "lib/notifications/email_copy.ex" => [%{module: "MyApp.Notifications.EmailCopy", function: "deliver", arity: 1}]
    }

    clones = %{
      "lib/notifications/email_copy.ex" => %{source: "lib/notifications/email.ex", similarity: 0.91}
    }

    metadata = %{
      "lib/support/data_case.ex" => %{injected_by: ["use MyApp.DataCase"]},
      "lib/notifications/email.ex" => %{
        behaviours: ["MyApp.Notifications"],
        sibling_implementations: ["lib/notifications/sms.ex"]
      }
    }

    output = Render.render_files(ranked_files, symbols, %{}, clones, metadata, 1_000)

    assert output =~ "injected via: use MyApp.DataCase"
    assert output =~ "behaviour: MyApp.Notifications"
    assert output =~ "sibling implementations: lib/notifications/sms.ex"
    assert output =~ "[CLONE of lib/notifications/email.ex, similarity: 0.91]"
    refute output =~ "MyApp.Notifications.EmailCopy"
  end
end
