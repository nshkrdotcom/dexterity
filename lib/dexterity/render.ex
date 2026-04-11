defmodule Dexterity.Render do
  @moduledoc """
  Renders ranked file data into deterministic Markdown.
  """
  alias Dexterity.Tokenizer

  @type file_block :: {String.t(), float()}

  @spec render_files([file_block()], map(), map(), map(), integer()) :: String.t()
  def render_files(ranked_files, symbols, summaries, clones, budget) do
    budget = max(budget, 1)

    {output, _} =
      Enum.reduce_while(ranked_files, {"", 0}, fn {file, score}, {acc, used} ->
        block = render_file(file, score, symbols[file] || [], summaries[file], clones[file])
        block_tokens = Tokenizer.count(block)

        if used + block_tokens > budget do
          {:halt, {acc, used}}
        else
          {:cont, {acc <> block, used + block_tokens}}
        end
      end)

    output
  end

  defp render_file(file, score, symbols, summary, clone_of) do
    base =
      ["## #{file}", "- rank: #{Float.round(score, 6)}"]
      |> Enum.join("\n")

    injection =
      if clone_of do
        ["- [CLONE of #{clone_of}]"]
      else
        []
      end

    summary_text =
      if summary do
        ["- summary: #{summary}"]
      else
        []
      end

    symbol_lines =
      symbols
      |> Enum.map(fn sym -> "- `#{sym.function}/#{sym.arity}` in `#{sym.module}`" end)

    content = Enum.join([base, injection, summary_text, symbol_lines], "\n")
    "\n#{content}\n"
  end
end
