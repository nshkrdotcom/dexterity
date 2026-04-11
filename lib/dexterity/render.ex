defmodule Dexterity.Render do
  @moduledoc """
  Renders ranked file data into deterministic Markdown.
  """
  alias Dexterity.Tokenizer

  @type file_block :: {String.t(), float()}

  @spec render_files([file_block()], map(), map(), map(), integer()) :: String.t()
  def render_files(ranked_files, symbols, summaries, clones, budget) do
    render_files(ranked_files, symbols, summaries, clones, %{}, budget)
  end

  @spec render_files([file_block()], map(), map(), map(), map(), integer()) :: String.t()
  def render_files(ranked_files, symbols, summaries, clones, metadata, budget) do
    budget = max(budget, 1)

    {output, _} =
      Enum.reduce_while(ranked_files, {"", 0}, fn {file, score}, {acc, used} ->
        block =
          render_file(
            file,
            score,
            symbols[file] || [],
            summaries[file],
            clones[file],
            metadata[file] || %{}
          )

        block_tokens = Tokenizer.count(block)

        if used + block_tokens > budget do
          {:halt, {acc, used}}
        else
          {:cont, {acc <> block, used + block_tokens}}
        end
      end)

    output
  end

  defp render_file(file, score, symbols, summary, clone_of, metadata) do
    base =
      ["## #{file_heading(file, metadata)}", "- rank: #{Float.round(score, 6)}"]
      |> Enum.join("\n")

    metadata_lines =
      []
      |> append_annotation("injected via", Map.get(metadata, :injected_by, []))
      |> append_annotation("uses", Map.get(metadata, :uses, []))
      |> append_annotation("behaviour", Map.get(metadata, :behaviours, []))
      |> append_annotation(
        "protocol implementation",
        Map.get(metadata, :protocol_implementations, [])
      )
      |> append_annotation(
        "sibling implementations",
        Map.get(metadata, :sibling_implementations, [])
      )

    summary_text =
      if summary do
        ["- summary: #{summary}"]
      else
        []
      end

    symbol_lines =
      if clone_of do
        []
      else
        Enum.map(symbols, fn sym -> "- `#{sym.function}/#{sym.arity}` in `#{sym.module}`" end)
      end

    content =
      ([base] ++ clone_line(clone_of) ++ metadata_lines ++ summary_text ++ symbol_lines)
      |> Enum.join("\n")

    "\n#{content}\n"
  end

  defp file_heading(file, metadata) do
    file <>
      blast_radius_tag(Map.get(metadata, :blast_radius, 0)) <>
      recency_tag(Map.get(metadata, :mtime))
  end

  defp blast_radius_tag(radius) when is_integer(radius) and radius > 0, do: " (→#{radius})"
  defp blast_radius_tag(_radius), do: ""

  defp recency_tag(nil), do: ""

  defp recency_tag(mtime) when is_integer(mtime) do
    recent_cutoff = System.os_time(:second) - 48 * 60 * 60

    if mtime >= recent_cutoff do
      " [NEW]"
    else
      ""
    end
  end

  defp recency_tag(_mtime), do: ""

  defp append_annotation(lines, _label, []), do: lines

  defp append_annotation(lines, label, values),
    do: lines ++ ["- #{label}: #{Enum.join(values, ", ")}"]

  defp clone_line(nil), do: []
  defp clone_line(clone_of) when is_binary(clone_of), do: ["- [CLONE of #{clone_of}]"]

  defp clone_line(%{source: source, similarity: similarity}) do
    rendered_similarity = :erlang.float_to_binary(similarity, decimals: 2)
    ["- [CLONE of #{source}, similarity: #{rendered_similarity}]"]
  end

  @spec render_symbols([map()], map(), MapSet.t(String.t()) | [String.t()], integer()) ::
          String.t()
  def render_symbols(ranked_symbols, source_snippets, changed_ids, budget) do
    changed_ids = MapSet.new(changed_ids)
    budget = max(budget, 1)

    {output, _used} =
      ranked_symbols
      |> Enum.with_index()
      |> Enum.reduce_while({"", 0}, fn {symbol, index}, {acc, used} ->
        block = render_symbol(symbol, index, source_snippets, changed_ids)
        block_tokens = Tokenizer.count(block)

        if used + block_tokens > budget do
          {:halt, {acc, used}}
        else
          {:cont, {acc <> block, used + block_tokens}}
        end
      end)

    output
  end

  defp render_symbol(symbol, index, source_snippets, changed_ids) do
    changed? = MapSet.member?(changed_ids, symbol.id)

    case render_tier(index) do
      :full ->
        snippet = Map.get(source_snippets, symbol.id, "")

        """

        ### #{symbol_heading(symbol, changed?)}
        - file: `#{symbol.file}`
        - rank: #{Float.round(symbol.rank, 6)}
        - signature: #{Map.get(symbol, :signature, "#{symbol.function}/#{symbol.arity}")}
        ```elixir
        #{String.trim(snippet)}
        ```
        """

      :signature ->
        """

        ### #{symbol_heading(symbol, changed?)}
        - file: `#{symbol.file}`
        - rank: #{Float.round(symbol.rank, 6)}
        - signature: #{Map.get(symbol, :signature, "#{symbol.function}/#{symbol.arity}")}
        """

      :compact ->
        "\n- `#{symbol.module}.#{symbol.function}/#{symbol.arity}` in `#{symbol.file}`\n"
    end
  end

  defp render_tier(0), do: :full
  defp render_tier(1), do: :signature
  defp render_tier(_index), do: :compact

  defp symbol_heading(symbol, true),
    do: "#{symbol.module}.#{symbol.function}/#{symbol.arity} [CHANGED]"

  defp symbol_heading(symbol, false), do: "#{symbol.module}.#{symbol.function}/#{symbol.arity}"
end
