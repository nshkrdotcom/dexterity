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
end
