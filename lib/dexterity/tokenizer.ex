defmodule Dexterity.Tokenizer do
  @moduledoc """
  Wraps tiktoken for token counting.
  """

  alias Dexterity.Config

  @doc """
  Counts the number of tokens in a string.
  """
  @spec count(String.t()) :: non_neg_integer()
  def count(text) do
    model = Config.token_model()

    case tiktoken_available?() and Tiktoken.encode(model, text) do
      {:ok, tokens} -> length(tokens)
      _ -> fallback_count(text)
    end
  end

  defp tiktoken_available? do
    Code.ensure_loaded?(Tiktoken) and function_exported?(Tiktoken, :encode, 2)
  end

  defp fallback_count(text) do
    # Fallback character approximation
    div(String.length(text), 4)
  end

  @doc false
  @spec ascii_word_terms(String.t()) :: [String.t()]
  def ascii_word_terms(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.to_charlist()
    |> scan_terms(:any_start, [], [])
  end

  def ascii_word_terms(_text), do: []

  @doc false
  @spec identifier_terms(String.t()) :: [String.t()]
  def identifier_terms(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.to_charlist()
    |> scan_terms(:identifier_start, [], [])
  end

  def identifier_terms(_text), do: []

  defp scan_terms([], _mode, [], acc), do: acc |> Enum.reverse() |> Enum.uniq() |> Enum.sort()

  defp scan_terms([], _mode, current, acc) do
    current
    |> emit_term(acc)
    |> Enum.reverse()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp scan_terms([char | rest], :any_start, current, acc) do
    if term_char?(char) do
      scan_terms(rest, :any_start, [char | current], acc)
    else
      scan_terms(rest, :any_start, [], emit_term(current, acc))
    end
  end

  defp scan_terms([char | rest], :identifier_start, [], acc) do
    if identifier_start_char?(char) do
      scan_terms(rest, :identifier_start, [char], acc)
    else
      scan_terms(rest, :identifier_start, [], acc)
    end
  end

  defp scan_terms([char | rest], :identifier_start, current, acc) do
    if term_char?(char) do
      scan_terms(rest, :identifier_start, [char | current], acc)
    else
      scan_terms(rest, :identifier_start, [], emit_term(current, acc))
    end
  end

  defp emit_term([], acc), do: acc

  defp emit_term(chars, acc) do
    [chars |> Enum.reverse() |> IO.iodata_to_binary() | acc]
  end

  defp identifier_start_char?(char), do: ascii_letter?(char) or char == ?_

  defp term_char?(char),
    do: identifier_start_char?(char) or ascii_digit?(char) or char in [?!, ??]

  defp ascii_letter?(char), do: (char >= ?a and char <= ?z) or (char >= ?A and char <= ?Z)
  defp ascii_digit?(char), do: char >= ?0 and char <= ?9
end
