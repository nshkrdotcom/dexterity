defmodule Dexterity.Tokenizer do
  @moduledoc """
  Wraps tiktoken for token counting.
  """

  @doc """
  Counts the number of tokens in a string.
  """
  @spec count(String.t()) :: non_neg_integer()
  def count(text) do
    case Tiktoken.encode("gpt-4", text) do
      {:ok, tokens} -> length(tokens)
      _ -> fallback_count(text)
    end
  end

  defp fallback_count(text) do
    # Fallback character approximation
    div(String.length(text), 4)
  end
end
