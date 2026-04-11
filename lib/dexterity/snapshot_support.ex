defmodule Dexterity.SnapshotSupport do
  @moduledoc false

  @spec fingerprint(term()) :: String.t()
  def fingerprint(term) do
    term
    |> normalize(term)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec normalize(term()) :: term()
  def normalize(term), do: normalize(term, term)

  defp normalize(%_struct{} = struct, _original) do
    struct
    |> Map.from_struct()
    |> normalize(nil)
  end

  defp normalize(map, _original) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {normalize(key, key), normalize(value, value)} end)
    |> Enum.sort_by(fn {key, _value} -> :erlang.term_to_binary(key) end)
  end

  defp normalize(list, _original) when is_list(list) do
    Enum.map(list, &normalize(&1, &1))
  end

  defp normalize(tuple, _original) when is_tuple(tuple) do
    {:tuple, tuple |> Tuple.to_list() |> Enum.map(&normalize(&1, &1))}
  end

  defp normalize(other, _original), do: other
end
