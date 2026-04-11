defmodule Dexterity.Entrypoints do
  @moduledoc false

  @type implicit_ref :: %{
          source: String.t(),
          function: String.t(),
          arity: non_neg_integer()
        }

  @type export_kind :: :callback_entrypoint | :public_api

  @macro_entrypoints %{
    "Mix.Project" => [
      {"project", 0},
      {"application", 0},
      {"deps", 0}
    ],
    "Phoenix.LiveView" => [
      {"mount", 3},
      {"handle_params", 3},
      {"handle_event", 3},
      {"handle_info", 2},
      {"render", 1},
      {"terminate", 2},
      {"update", 2}
    ],
    "Phoenix.Component" => [{"render", 1}]
  }

  @use_behaviour_registry %{
    "Application" => ["Application"],
    "GenServer" => ["GenServer"],
    "Supervisor" => ["Supervisor"],
    "Plug" => ["Plug"],
    "Plug.Builder" => ["Plug"],
    "Plug.Router" => ["Plug"]
  }

  @behaviour_fallbacks %{
    "Plug" => [call: 2, init: 1]
  }

  @spec classify(map(), map()) :: %{kind: export_kind(), implicit_refs: [implicit_ref()]}
  def classify(symbol, metadata) do
    implicit_refs = implicit_refs(symbol, metadata)

    %{
      kind: if(implicit_refs == [], do: :public_api, else: :callback_entrypoint),
      implicit_refs: implicit_refs
    }
  end

  @spec implicit_refs(map(), map()) :: [implicit_ref()]
  def implicit_refs(symbol, metadata) do
    metadata
    |> candidate_callbacks()
    |> Enum.filter(fn callback ->
      callback.function == Map.get(symbol, :function) and
        callback.arity == Map.get(symbol, :arity)
    end)
    |> Enum.uniq_by(fn callback -> {callback.source, callback.function, callback.arity} end)
    |> Enum.sort_by(fn callback -> {callback.source, callback.function, callback.arity} end)
  end

  defp candidate_callbacks(metadata) do
    macro_callbacks =
      metadata
      |> Map.get(:uses, [])
      |> Enum.flat_map(&callbacks_from_macro_use/1)

    behaviour_callbacks =
      metadata
      |> Map.get(:behaviours, [])
      |> Enum.flat_map(&callbacks_from_behaviour/1)

    protocol_callbacks =
      metadata
      |> Map.get(:protocol_implementations, [])
      |> Enum.flat_map(&callbacks_from_protocol/1)

    macro_callbacks ++ behaviour_callbacks ++ protocol_callbacks
  end

  defp callbacks_from_macro_use(module_name) do
    direct =
      @macro_entrypoints
      |> Map.get(module_name, [])
      |> Enum.map(fn {function, arity} ->
        %{source: "use #{module_name}", function: function, arity: arity}
      end)

    behaviour_callbacks =
      @use_behaviour_registry
      |> Map.get(module_name, [])
      |> Enum.flat_map(&callbacks_from_behaviour/1)

    direct ++ behaviour_callbacks
  end

  defp callbacks_from_behaviour(module_name) do
    module_name
    |> callback_pairs()
    |> Enum.map(fn {function, arity} ->
      %{source: "behaviour #{module_name}", function: Atom.to_string(function), arity: arity}
    end)
  end

  defp callbacks_from_protocol(module_name) do
    module_name
    |> callback_pairs()
    |> Enum.map(fn {function, arity} ->
      %{source: "protocol #{module_name}", function: Atom.to_string(function), arity: arity}
    end)
  end

  defp callback_pairs(module_name) do
    case existing_module(module_name) do
      {:ok, module} ->
        if function_exported?(module, :behaviour_info, 1) do
          module.behaviour_info(:callbacks)
        else
          Map.get(@behaviour_fallbacks, module_name, [])
        end

      _ ->
        Map.get(@behaviour_fallbacks, module_name, [])
    end
  end

  defp existing_module(module_name) do
    [module_name, "Elixir." <> module_name]
    |> Enum.find_value({:error, :not_loaded}, fn candidate ->
      try do
        module = String.to_existing_atom(candidate)

        if Code.ensure_loaded?(module) do
          {:ok, module}
        end
      rescue
        ArgumentError -> nil
      end
    end)
  end
end
