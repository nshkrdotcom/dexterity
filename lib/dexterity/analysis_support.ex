defmodule Dexterity.AnalysisSupport do
  @moduledoc false

  alias Dexterity.GraphServer
  alias Dexterity.Metadata

  @spec collect_symbols(module(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def collect_symbols(backend, repo_root) do
    with {:ok, files} <- backend.list_file_nodes(repo_root) do
      files
      |> Enum.filter(&project_file?(repo_root, &1))
      |> Enum.uniq()
      |> Enum.reduce_while({:ok, []}, fn file, {:ok, acc} ->
        case backend.list_exported_symbols(repo_root, file) do
          {:ok, symbols} ->
            project_symbols =
              Enum.filter(symbols, fn symbol ->
                project_file?(repo_root, Map.get(symbol, :file, file))
              end)

            {:cont, {:ok, acc ++ project_symbols}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
    end
  end

  @spec project_file?(String.t(), term()) :: boolean()
  def project_file?(repo_root, file) when is_binary(file) do
    if Path.type(file) == :absolute do
      expanded_root = Path.expand(repo_root) <> "/"
      expanded_file = Path.expand(file)
      String.starts_with?(expanded_file, expanded_root)
    else
      true
    end
  end

  def project_file?(_repo_root, _file), do: false

  @spec baseline_rank(term()) :: %{String.t() => float()}
  def baseline_rank(graph_server) do
    try do
      case GraphServer.get_baseline_rank(graph_server) do
        ranks when is_map(ranks) -> ranks
        _ -> %{}
      end
    catch
      :exit, _reason -> %{}
    end
  rescue
    _ -> %{}
  end

  @spec metadata_map(module(), String.t(), term()) :: %{String.t() => map()}
  def metadata_map(backend, repo_root, graph_server) do
    case fetch_graph_metadata(graph_server) do
      {:ok, metadata} when is_map(metadata) ->
        metadata

      _ ->
        fallback_metadata(backend, repo_root)
    end
  end

  @spec test_path?(term()) :: boolean()
  def test_path?(path) when is_binary(path) do
    lowered = String.downcase(path)

    String.starts_with?(lowered, "test/") or
      String.starts_with?(lowered, "spec/") or
      String.contains?(lowered, "/test/") or
      String.contains?(lowered, "/spec/") or
      String.ends_with?(lowered, "_test.exs") or
      String.ends_with?(lowered, "_spec.exs")
  end

  def test_path?(_path), do: false

  defp fetch_graph_metadata(nil), do: {:error, :graph_unavailable}

  defp fetch_graph_metadata(graph_server) do
    {:ok, GraphServer.get_metadata(graph_server)}
  rescue
    _ -> {:error, :graph_unavailable}
  catch
    :exit, _reason -> {:error, :graph_unavailable}
  end

  defp fallback_metadata(backend, repo_root) do
    case backend.list_file_nodes(repo_root) do
      {:ok, files} ->
        Metadata.build(repo_root, files).files

      _ ->
        %{}
    end
  end
end
