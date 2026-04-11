defmodule Dexterity.Metadata do
  @moduledoc false

  @type file_metadata :: %{
          modules: [String.t()],
          moduledoc: String.t() | nil,
          uses: [String.t()],
          behaviours: [String.t()],
          protocol_implementations: [String.t()],
          injected_by: [String.t()],
          sibling_implementations: [String.t()],
          clone_tokens: [String.t()],
          search_terms: [String.t()],
          mtime: integer(),
          blast_radius: non_neg_integer()
        }

  @spec build(String.t(), [String.t()]) :: %{
          files: %{String.t() => file_metadata()},
          edges: [tuple()]
        }
  def build(repo_root, files) do
    files =
      files
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Enum.sort()

    file_metadata =
      Map.new(files, fn file ->
        {file, analyze_file(repo_root, file)}
      end)

    module_to_file =
      file_metadata
      |> Enum.flat_map(fn {file, metadata} ->
        Enum.map(metadata.modules, &{&1, file})
      end)
      |> Enum.reduce(%{}, fn {module_name, file}, acc ->
        Map.put_new(acc, module_name, file)
      end)

    use_edges =
      Enum.flat_map(file_metadata, fn {file, metadata} ->
        Enum.flat_map(metadata.uses, fn module_name ->
          case Map.get(module_to_file, module_name) do
            nil ->
              []

            target_file when target_file == file ->
              []

            target_file ->
              [{file, target_file, 3.0, "use #{module_name}"}]
          end
        end)
      end)

    behaviour_groups =
      group_implementations(file_metadata, :behaviours)

    protocol_groups =
      group_implementations(file_metadata, :protocol_implementations)

    sibling_implementations =
      sibling_implementations(behaviour_groups, protocol_groups)

    reverse_edges =
      implementation_reverse_edges(file_metadata, module_to_file)

    sibling_edges =
      sibling_edges(behaviour_groups) ++ sibling_edges(protocol_groups)

    injected_by =
      Enum.reduce(use_edges, %{}, fn {_source_file, target_file, _weight, reason}, acc ->
        Map.update(acc, target_file, [reason], fn reasons ->
          [reason | reasons]
          |> Enum.uniq()
          |> Enum.sort()
        end)
      end)

    enriched_files =
      Map.new(file_metadata, fn {file, metadata} ->
        {file,
         metadata
         |> Map.put(:injected_by, Map.get(injected_by, file, []))
         |> Map.put(:sibling_implementations, Map.get(sibling_implementations, file, []))}
      end)

    edges =
      use_edges
      |> Enum.map(fn {source, target, weight, _reason} -> {source, target, weight} end)
      |> Kernel.++(reverse_edges)
      |> Kernel.++(sibling_edges)

    %{files: enriched_files, edges: edges}
  end

  @spec summary_entry(file_metadata() | nil, [map()]) ::
          nil | %{module_name: String.t(), context: map(), signature: binary()}
  def summary_entry(nil, _symbols), do: nil

  def summary_entry(metadata, symbols) do
    modules = Map.get(metadata, :modules, [])

    module_name =
      case symbols do
        [%{module: module_name} | _] when is_binary(module_name) -> module_name
        _ -> List.first(modules)
      end

    if is_binary(module_name) do
      exports =
        symbols
        |> Enum.map(fn symbol -> "#{symbol.function}/#{symbol.arity}" end)
        |> Enum.sort()

      context = %{
        module: module_name,
        moduledoc: Map.get(metadata, :moduledoc),
        exports: exports
      }

      %{module_name: module_name, context: context, signature: summary_signature(context)}
    end
  end

  @spec summary_signature(term()) :: binary()
  def summary_signature(context) do
    :crypto.hash(:sha256, :erlang.term_to_binary(context))
  end

  @spec clone_signature(file_metadata() | nil) :: nil | binary()
  def clone_signature(nil), do: nil

  def clone_signature(metadata) do
    case Map.get(metadata, :clone_tokens, []) do
      [] -> nil
      tokens -> :erlang.term_to_binary(tokens)
    end
  end

  @spec clone_tokens(file_metadata() | nil) :: [String.t()]
  def clone_tokens(nil), do: []
  def clone_tokens(metadata), do: Map.get(metadata, :clone_tokens, [])

  @spec primary_module(file_metadata() | nil, String.t()) :: String.t()
  def primary_module(nil, file), do: file
  def primary_module(metadata, file), do: List.first(Map.get(metadata, :modules, [])) || file

  defp group_implementations(file_metadata, key) do
    Enum.reduce(file_metadata, %{}, fn {file, metadata}, acc ->
      Enum.reduce(Map.get(metadata, key, []), acc, fn module_name, group_acc ->
        Map.update(group_acc, module_name, [file], fn files ->
          [file | files]
          |> Enum.uniq()
          |> Enum.sort()
        end)
      end)
    end)
  end

  defp implementation_reverse_edges(file_metadata, module_to_file) do
    Enum.flat_map(file_metadata, fn {file, metadata} ->
      modules = metadata.behaviours ++ metadata.protocol_implementations

      Enum.flat_map(modules, fn module_name ->
        case Map.get(module_to_file, module_name) do
          nil ->
            []

          target_file when target_file == file ->
            []

          target_file ->
            [{file, target_file, 2.0}]
        end
      end)
    end)
  end

  defp sibling_edges(groups) do
    Enum.flat_map(groups, fn {_module_name, files} ->
      for source <- files,
          target <- files,
          source != target do
        {source, target, 0.5}
      end
    end)
  end

  defp sibling_implementations(behaviour_groups, protocol_groups) do
    [behaviour_groups, protocol_groups]
    |> Enum.flat_map(&Map.values/1)
    |> Enum.reduce(%{}, fn files, acc ->
      Enum.reduce(files, acc, fn file, inner_acc ->
        siblings =
          files
          |> Enum.reject(&(&1 == file))
          |> Enum.sort()

        Map.update(inner_acc, file, siblings, fn existing ->
          (existing ++ siblings)
          |> Enum.uniq()
          |> Enum.sort()
        end)
      end)
    end)
  end

  defp analyze_file(repo_root, file) do
    path = Path.join(repo_root, file)

    if File.regular?(path) do
      source = File.read!(path)
      mtime = file_mtime(path)

      case Code.string_to_quoted(source, file: path, emit_warnings: false) do
        {:ok, ast} ->
          ast
          |> collect_metadata()
          |> Map.put(:clone_tokens, clone_tokens_from_ast(ast))
          |> Map.put(:search_terms, tokenize(source))
          |> Map.put(:mtime, mtime)

        {:error, _reason} ->
          empty_metadata()
          |> Map.put(:clone_tokens, tokenize(source))
          |> Map.put(:search_terms, tokenize(source))
          |> Map.put(:mtime, mtime)
      end
    else
      empty_metadata()
    end
  end

  defp collect_metadata(ast) do
    {_ast, metadata} =
      Macro.prewalk(ast, empty_metadata(), fn
        {:defmodule, _meta, [module_ast | _rest]} = node, acc ->
          {node, update_list(acc, :modules, alias_to_string(module_ast))}

        {:defprotocol, _meta, [module_ast | _rest]} = node, acc ->
          {node, update_list(acc, :modules, alias_to_string(module_ast))}

        {:defimpl, _meta, [protocol_ast | _rest]} = node, acc ->
          {node, update_list(acc, :protocol_implementations, alias_to_string(protocol_ast))}

        {:use, _meta, [module_ast | _rest]} = node, acc ->
          {node, update_list(acc, :uses, alias_to_string(module_ast))}

        {:@, _meta, [{:behaviour, _, [module_ast]}]} = node, acc ->
          {node, update_list(acc, :behaviours, alias_to_string(module_ast))}

        {:@, _meta, [{:moduledoc, _, [value]}]} = node, acc ->
          {node, Map.put(acc, :moduledoc, normalize_doc(value))}

        node, acc ->
          {node, acc}
      end)

    metadata
  end

  defp clone_tokens_from_ast(ast) do
    ast
    |> normalize_ast()
    |> Macro.to_string()
    |> tokenize()
  end

  defp normalize_ast(ast) do
    Macro.prewalk(ast, fn
      {:@, meta, [{attr, _, _}]} when attr in [:doc, :moduledoc, :typedoc] ->
        {:doc_attribute, meta, []}

      {name, meta, context} when is_atom(name) and (is_atom(context) or is_nil(context)) ->
        {:var, meta, context}

      binary when is_binary(binary) ->
        "__string__"

      number when is_number(number) ->
        0

      node ->
        node
    end)
  end

  defp tokenize(string) do
    string
    |> then(&Regex.scan(~r/[A-Za-z_][A-Za-z0-9_!?]*/, &1))
    |> List.flatten()
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp alias_to_string({:__aliases__, _, parts}), do: Enum.join(parts, ".")

  defp alias_to_string(atom) when is_atom(atom),
    do: atom |> Atom.to_string() |> String.trim_leading("Elixir.")

  defp alias_to_string(_), do: nil

  defp update_list(metadata, _key, nil), do: metadata

  defp update_list(metadata, key, value) do
    Map.update!(metadata, key, fn values ->
      [value | values]
      |> Enum.uniq()
      |> Enum.sort()
    end)
  end

  defp normalize_doc(value) when is_binary(value), do: value
  defp normalize_doc(_value), do: nil

  defp file_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> stat.mtime
      _ -> 0
    end
  end

  defp empty_metadata do
    %{
      modules: [],
      moduledoc: nil,
      uses: [],
      behaviours: [],
      protocol_implementations: [],
      injected_by: [],
      sibling_implementations: [],
      clone_tokens: [],
      search_terms: [],
      mtime: 0,
      blast_radius: 0
    }
  end
end
