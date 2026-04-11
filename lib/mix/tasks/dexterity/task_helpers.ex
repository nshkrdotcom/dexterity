defmodule Mix.Tasks.Dexterity.TaskHelpers do
  @moduledoc false

  alias Dexterity.Config

  @backend_callback_keys [
    {:cold_index, 2},
    {:index_status, 1},
    {:healthy?, 1},
    {:list_file_edges, 1}
  ]

  @task_repo_root_key :repo_root
  @task_backend_key :backend

  @spec parse_backend(keyword()) :: module()
  def parse_backend(opts) do
    backend = Keyword.get(opts, @task_backend_key, Config.fetch(:backend))
    normalize_module!(backend)
  end

  @spec parse_repo_root(keyword()) :: String.t()
  def parse_repo_root(opts) do
    Keyword.get(opts, @task_repo_root_key, Config.repo_root())
  end

  @spec ensure_started!() :: :ok
  def ensure_started! do
    Mix.Task.reenable("app.start")
    Mix.Task.run("app.start", [])
    :ok
  end

  @spec configure_temporary(keyword(), (() -> result)) :: result when result: var
  def configure_temporary(extra_config, fun) do
    previous =
      extra_config
      |> Enum.map(fn {key, _value} ->
        {key, Application.get_env(:dexterity, key)}
      end)

    try do
      Enum.each(extra_config, fn {key, value} ->
        Application.put_env(:dexterity, key, value)
      end)

      ensure_started!()
      fun.()
    after
      Enum.each(previous, fn {key, value} ->
        if value == nil do
          Application.delete_env(:dexterity, key)
        else
          Application.put_env(:dexterity, key, value)
        end
      end)
    end
  end

  @spec exit_with_error(String.t(), term()) :: no_return()
  def exit_with_error(message, reason) do
    Mix.shell().error("#{message}: #{inspect(reason)}")
    raise Mix.Error, message: message
  end

  @spec parse_int!(String.t(), term()) :: integer()
  def parse_int!(_name, value) when is_integer(value), do: value

  def parse_int!(name, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> raise ArgumentError, "invalid integer for #{name}: #{inspect(value)}"
    end
  end

  def parse_int!(name, value) do
    raise ArgumentError, "invalid integer for #{name}: #{inspect(value)}"
  end

  @spec parse_file_list(keyword(), atom()) :: [String.t()]
  def parse_file_list(opts, key) do
    opts
    |> Keyword.get_values(key)
    |> Enum.flat_map(fn
      value when is_binary(value) ->
        String.split(value, ",", trim: true)

      value ->
        [value]
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  @spec parse_include_clones(keyword()) :: boolean()
  def parse_include_clones(opts) do
    Keyword.get(opts, :include_clones, Config.fetch(:include_clones))
  end

  @spec parse_token_budget(keyword()) :: :auto | integer()
  def parse_token_budget(opts) do
    budget = Keyword.get(opts, :token_budget, :auto)

    if budget in [:auto, "auto", nil] do
      :auto
    else
      parse_int!("token budget", budget)
    end
  end

  @spec parse_limit(keyword()) :: integer()
  def parse_limit(opts) do
    parse_int!("limit", Keyword.get(opts, :limit, 25))
  end

  @spec parse_depth(keyword(), integer()) :: integer()
  def parse_depth(opts, fallback) do
    parse_int!("depth", Keyword.get(opts, :depth, fallback))
  end

  @spec print_error_result(term()) :: no_return()
  def print_error_result(reason) do
    exit_with_error("command failed", reason)
  end

  @spec print_rendered_map(String.t()) :: :ok
  def print_rendered_map(output) do
    Mix.shell().info(output)
    :ok
  end

  @spec print_value(term()) :: :ok
  def print_value(value) do
    Mix.shell().info(inspect(value, pretty: true, width: 80))
    :ok
  end

  @spec normalize_module!(module() | String.t()) :: module()
  defp normalize_module!(module) when is_atom(module), do: ensure_backend_behaviour!(module)

  defp normalize_module!(value) when is_binary(value) do
    module = Module.concat([value])
    ensure_backend_behaviour!(module)
  end

  defp normalize_module!(value) do
    raise ArgumentError, "invalid backend value: #{inspect(value)}"
  end

  @spec ensure_backend_behaviour!(module()) :: module()
  defp ensure_backend_behaviour!(module) when is_atom(module) do
    unless function_exported?(module, :cold_index, 2) do
      raise ArgumentError,
            "module #{inspect(module)} does not satisfy Dexterity.Backend contract"
    end

    Enum.each(@backend_callback_keys, fn {func, arity} ->
      unless function_exported?(module, func, arity) do
        raise ArgumentError,
              "module #{inspect(module)} does not implement #{func}/#{arity}"
      end
    end)

    module
  end
end
