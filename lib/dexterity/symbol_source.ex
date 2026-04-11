defmodule Dexterity.SymbolSource do
  @moduledoc false

  @type symbol_node :: %{
          required(:id) => String.t(),
          required(:module) => String.t(),
          required(:function) => String.t(),
          required(:arity) => non_neg_integer(),
          required(:file) => String.t(),
          required(:line) => pos_integer(),
          required(:end_line) => pos_integer(),
          required(:signature) => String.t(),
          required(:visibility) => :public | :private,
          required(:kind) => String.t()
        }

  @spec enrich(String.t(), [map()]) :: [symbol_node()]
  def enrich(repo_root, symbols) do
    symbols
    |> Enum.filter(&valid_symbol?/1)
    |> Enum.group_by(& &1.file)
    |> Enum.flat_map(fn {file, file_symbols} ->
      sorted_symbols = Enum.sort_by(file_symbols, &{&1.line, &1.module, &1.function, &1.arity})
      lines = file_lines(repo_root, file)
      max_line = max(length(lines), 1)

      sorted_symbols
      |> Enum.with_index()
      |> Enum.map(fn {symbol, index} ->
        next_symbol = Enum.at(sorted_symbols, index + 1)

        end_line =
          cond do
            is_integer(Map.get(symbol, :end_line)) and symbol.end_line >= symbol.line ->
              max(min(symbol.end_line, max_line), symbol.line)

            is_map(next_symbol) and is_integer(next_symbol.line) ->
              max(min(next_symbol.line - 1, max_line), symbol.line)

            true ->
              max(max_line, symbol.line)
          end

        symbol
        |> Map.put(:file, normalize_file(file))
        |> Map.put(:id, symbol_id(symbol))
        |> Map.put(:end_line, end_line)
        |> Map.put(:signature, normalize_signature(symbol, lines, end_line))
        |> Map.put(:visibility, normalize_visibility(symbol))
        |> Map.put(:kind, normalize_kind(symbol))
      end)
    end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{&1.file, &1.line, &1.module, &1.function, &1.arity})
  end

  @spec snippets(String.t(), [map()]) :: %{String.t() => String.t()}
  def snippets(repo_root, symbols) do
    repo_root
    |> enrich(symbols)
    |> Enum.group_by(& &1.file)
    |> Enum.reduce(%{}, fn {file, file_symbols}, acc ->
      lines = file_lines(repo_root, file)

      Enum.reduce(file_symbols, acc, fn symbol, inner_acc ->
        snippet_length = max(symbol.end_line - symbol.line + 1, 0)

        snippet =
          lines
          |> Enum.slice(max(symbol.line - 1, 0), snippet_length)
          |> trim_blank_edges()
          |> Enum.join("\n")
          |> String.trim_trailing()

        Map.put(inner_acc, symbol.id, snippet)
      end)
    end)
  end

  @spec symbol_id(%{
          required(:module) => term(),
          required(:function) => term(),
          required(:arity) => term(),
          required(:file) => String.t()
        }) :: String.t()
  def symbol_id(%{module: module, function: function, arity: arity, file: file}) do
    "#{module}.#{function}/#{arity}@#{normalize_file(file)}"
  end

  defp valid_symbol?(%{module: module, function: function, arity: arity, file: file, line: line})
       when is_binary(module) and is_binary(function) and is_integer(arity) and arity >= 0 and
              is_binary(file) and is_integer(line) and line > 0,
       do: true

  defp valid_symbol?(_symbol), do: false

  defp normalize_file(file) when is_binary(file), do: file

  defp file_lines(repo_root, file) do
    path =
      if Path.type(file) == :absolute do
        file
      else
        Path.join(repo_root, file)
      end

    if File.regular?(path) do
      path
      |> File.read!()
      |> String.split("\n")
    else
      []
    end
  rescue
    _ -> []
  end

  defp normalize_signature(symbol, lines, end_line) do
    case Map.get(symbol, :signature) do
      signature when is_binary(signature) and signature != "" ->
        signature

      _ ->
        start_line = symbol.line
        range_end = min(end_line, start_line + 5)

        lines
        |> Enum.slice(start_line - 1, range_end - start_line + 1)
        |> take_signature_lines()
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" ")
        |> String.replace(~r/\s+/, " ")
        |> String.replace(~r/\s+do\s*$/, "")
        |> String.replace(~r/\s*,\s*do:\s*.*$/, "")
        |> case do
          "" -> "#{normalize_kind(symbol)} #{symbol.function}/#{symbol.arity}"
          inferred_signature -> inferred_signature
        end
    end
  end

  defp take_signature_lines(lines) do
    Enum.reduce_while(lines, [], fn line, acc ->
      trimmed = String.trim(line)
      next = acc ++ [line]

      signature_step(trimmed, acc, next)
    end)
  end

  defp signature_step("", [], _next), do: {:cont, []}

  defp signature_step(trimmed, acc, next) do
    cond do
      String.contains?(trimmed, ", do:") ->
        {:halt, next}

      String.ends_with?(trimmed, " do") ->
        {:halt, next}

      String.ends_with?(trimmed, ")") and acc != [] ->
        {:halt, next}

      String.starts_with?(trimmed, "@") and acc != [] ->
        {:halt, acc}

      true ->
        {:cont, next}
    end
  end

  defp normalize_visibility(symbol) do
    case Map.get(symbol, :visibility) do
      visibility when visibility in [:public, :private] ->
        visibility

      _ ->
        if String.ends_with?(normalize_kind(symbol), "p") do
          :private
        else
          :public
        end
    end
  end

  defp normalize_kind(symbol) do
    case Map.get(symbol, :kind) do
      kind when is_binary(kind) and kind != "" -> kind
      _ -> "def"
    end
  end

  defp trim_blank_edges(lines) do
    lines
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> Enum.reverse()
  end
end
