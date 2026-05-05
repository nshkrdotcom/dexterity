defmodule Dexterity.BackendResolver do
  @moduledoc false

  @builtin_backend_refs %{
    "dexter" => Dexterity.Backend.Dexter,
    "mock" => Dexterity.Backend.Mock
  }

  @builtin_backend_names %{
    "Dexterity.Backend.Dexter" => Dexterity.Backend.Dexter,
    "Elixir.Dexterity.Backend.Dexter" => Dexterity.Backend.Dexter,
    "Dexterity.Backend.Mock" => Dexterity.Backend.Mock,
    "Elixir.Dexterity.Backend.Mock" => Dexterity.Backend.Mock
  }

  @spec resolve!(module() | String.t()) :: module()
  def resolve!(module) when is_atom(module), do: ensure_backend_behaviour!(module)

  def resolve!(value) when is_binary(value) do
    normalized = String.trim(value)

    module =
      Map.get(@builtin_backend_names, normalized) ||
        Map.get(@builtin_backend_refs, normalized) ||
        loaded_module_named(normalized)

    case module do
      nil ->
        raise ArgumentError, "unknown backend module: #{inspect(value)}"

      module when is_atom(module) ->
        ensure_backend_behaviour!(module)
    end
  end

  def resolve!(value) do
    raise ArgumentError, "invalid backend value: #{inspect(value)}"
  end

  @spec fetch_builtin_ref(String.t()) :: {:ok, module()} | :error
  def fetch_builtin_ref(ref) when is_binary(ref) do
    case Map.fetch(@builtin_backend_refs, ref) do
      {:ok, module} -> {:ok, resolve!(module)}
      :error -> :error
    end
  end

  def fetch_builtin_ref(_ref), do: :error

  defp loaded_module_named(name) do
    :code.all_loaded()
    |> Enum.find_value(fn {module, _path} ->
      if loaded_module_name?(module, name), do: module
    end)
  end

  defp loaded_module_name?(module, name) do
    inspect(module) == name or Atom.to_string(module) == name
  end

  @spec ensure_backend_behaviour!(module()) :: module()
  defp ensure_backend_behaviour!(module) when is_atom(module) do
    unless Code.ensure_loaded?(module) do
      raise ArgumentError,
            "module #{inspect(module)} does not satisfy Dexterity.Backend contract"
    end

    optional_callbacks =
      Dexterity.Backend.behaviour_info(:optional_callbacks)
      |> MapSet.new()

    Dexterity.Backend.behaviour_info(:callbacks)
    |> Enum.reject(&MapSet.member?(optional_callbacks, &1))
    |> Enum.each(fn {func, arity} ->
      unless function_exported?(module, func, arity) do
        raise ArgumentError,
              "module #{inspect(module)} does not implement #{func}/#{arity}"
      end
    end)

    module
  end
end
