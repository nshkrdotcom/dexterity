defmodule Dexterity.Render do
  @moduledoc """
  Handles token-bounded Markdown rendering of the context map.
  """

  alias Dexterity.Tokenizer

  @doc """
  Renders ranked files, symbols, and summaries into a Markdown string
  up to the provided token budget.
  """
  @spec render_files([{String.t(), float()}], map(), map(), map(), integer()) :: String.t()
  def render_files(ranked_files, symbols, summaries, clones, budget) do
    {output, _} =
      Enum.reduce_while(ranked_files, {"", 0}, fn {file, score}, {out, tokens} ->
        block = render_file_block(file, score, symbols[file] || [], summaries[file], clones[file])
        block_tokens = Tokenizer.count(block)

        if tokens + block_tokens > budget do
          {:halt, {out, tokens}}
        else
          {:cont, {out <> block, tokens + block_tokens}}
        end
      end)

    output
  end

  defp render_file_block(file, score, symbols, summary, clone_of) do
    header = "### #{file}  [rank: #{Float.round(score, 4)}]\n"

    if clone_of do
      header <> "> [CLONE of #{clone_of}]\n\n"
    else
      summary_text = if summary, do: "> #{summary}\n", else: ""

      symbols_text =
        Enum.map_join(symbols, "\n", fn sym ->
          "  def #{sym.function}/#{sym.arity}"
        end)

      header <> summary_text <> symbols_text <> "\n\n"
    end
  end
end
