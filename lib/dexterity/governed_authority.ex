defmodule Dexterity.GovernedAuthority do
  @moduledoc false

  alias Dexterity.BackendResolver

  @direct_fields [
    :repo_root,
    :backend,
    :dexter_bin,
    :dexter_db,
    :store_path,
    :mcp_enabled,
    :command_env,
    :env,
    :tool_config
  ]

  @required_refs [
    :authority_ref,
    :tool_ref,
    :operation_ref,
    :repo_ref,
    :backend_ref,
    :command_ref,
    :credential_ref
  ]

  @tool_refs ["dexterity.api", "dexterity.cli", "dexterity.mcp"]

  @operation_refs [
    "analysis",
    "impact_context",
    "index",
    "map",
    "mcp_serve",
    "query",
    "repo_map",
    "status",
    "structural_snapshot"
  ]

  @governed_cli_fields [
    :governed_authority_ref,
    :governed_tool_ref,
    :governed_operation_ref,
    :governed_repo_ref,
    :governed_backend_ref,
    :governed_command_ref,
    :governed_credential_ref,
    :governed_repo_root,
    :governed_dexter_bin,
    :governed_dexter_db,
    :governed_store_path,
    :governed_mcp_enabled,
    :governed_credential_value
  ]

  @type materialize_result :: {:ok, keyword()} | {:error, term()}

  @spec materialize_opts(keyword()) :: materialize_result()
  def materialize_opts(opts) when is_list(opts) do
    case Keyword.fetch(opts, :governed_authority) do
      :error ->
        {:ok, opts}

      {:ok, authority} ->
        with :ok <- reject_direct_fields(opts),
             {:ok, materialized} <- materialize(authority) do
          retained = Keyword.delete(opts, :governed_authority)
          {:ok, Keyword.merge(retained, materialized)}
        end
    end
  end

  @spec materialize_opts!(keyword()) :: keyword()
  def materialize_opts!(opts) do
    case materialize_opts(opts) do
      {:ok, materialized} ->
        materialized

      {:error, reason} ->
        raise ArgumentError, "invalid governed authority: #{inspect(reason)}"
    end
  end

  @spec authority_from_cli(keyword()) :: map() | nil
  def authority_from_cli(opts) do
    case Keyword.get(opts, :governed_authority_ref) do
      nil ->
        nil

      authority_ref ->
        %{
          authority_ref: authority_ref,
          tool_ref: Keyword.get(opts, :governed_tool_ref),
          operation_ref: Keyword.get(opts, :governed_operation_ref),
          repo_ref: Keyword.get(opts, :governed_repo_ref),
          backend_ref: Keyword.get(opts, :governed_backend_ref),
          command_ref: Keyword.get(opts, :governed_command_ref),
          credential_ref: Keyword.get(opts, :governed_credential_ref),
          repo_root: Keyword.get(opts, :governed_repo_root),
          dexter_bin: Keyword.get(opts, :governed_dexter_bin),
          dexter_db: Keyword.get(opts, :governed_dexter_db),
          store_path: Keyword.get(opts, :governed_store_path),
          mcp_enabled: parse_bool(Keyword.get(opts, :governed_mcp_enabled)),
          credential_value: Keyword.get(opts, :governed_credential_value)
        }
        |> drop_nil_values()
    end
  end

  @spec governed_cli?(keyword()) :: boolean()
  def governed_cli?(opts), do: authority_from_cli(opts) != nil

  @spec materialize_cli_opts(keyword()) :: materialize_result()
  def materialize_cli_opts(opts) do
    case authority_from_cli(opts) do
      nil ->
        {:ok, opts}

      authority ->
        opts
        |> reject_direct_cli_fields()
        |> case do
          :ok ->
            retained = Keyword.drop(opts, @governed_cli_fields)
            materialize_opts([{:governed_authority, authority} | retained])

          {:error, _reason} = error ->
            error
        end
    end
  end

  @spec materialize_cli_opts!(keyword()) :: keyword()
  def materialize_cli_opts!(opts) do
    case materialize_cli_opts(opts) do
      {:ok, materialized} ->
        materialized

      {:error, {:direct_governed_config, fields}} ->
        raise Mix.Error,
          message: "direct config cannot accompany governed authority: #{inspect(fields)}"

      {:error, reason} ->
        raise Mix.Error, message: "invalid governed authority: #{inspect(reason)}"
    end
  end

  @spec redaction_values(keyword()) :: [String.t()]
  def redaction_values(opts) do
    opts
    |> Keyword.get(:redaction_values, [])
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @spec redact(String.t(), [String.t()]) :: String.t()
  def redact(value, redaction_values) when is_binary(value) and is_list(redaction_values) do
    redaction_values
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce(value, fn redaction_value, acc ->
      String.replace(acc, redaction_value, "[REDACTED]")
    end)
  end

  def redact(value, _redaction_values), do: value

  defp materialize(authority) do
    with {:ok, normalized} <- normalize_authority(authority),
         :ok <- validate_required_refs(normalized),
         :ok <- validate_known_ref(normalized, :tool_ref, @tool_refs),
         :ok <- validate_known_ref(normalized, :operation_ref, @operation_refs),
         {:ok, backend} <- backend_for(normalized),
         {:ok, repo_root} <- required_binary(normalized, :repo_root),
         {:ok, dexter_bin} <- required_binary(normalized, :dexter_bin) do
      dexter_db = optional_binary(normalized, :dexter_db, ".dexter.db")

      store_path =
        optional_binary(normalized, :store_path, {:project_relative, ".dexterity/dexterity.db"})

      mcp_enabled = optional_boolean(normalized, :mcp_enabled, false)
      credential_value = optional_binary(normalized, :credential_value, nil)

      values =
        [dexter_bin, credential_value]
        |> Enum.filter(&is_binary/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()

      {:ok,
       [
         repo_root: Path.expand(repo_root),
         backend: backend,
         dexter_bin: dexter_bin,
         dexter_db: dexter_db,
         store_path: store_path,
         mcp_enabled: mcp_enabled,
         governed_authority_ref: fetch(normalized, :authority_ref),
         governed_tool_ref: fetch(normalized, :tool_ref),
         governed_operation_ref: fetch(normalized, :operation_ref),
         governed_repo_ref: fetch(normalized, :repo_ref),
         governed_backend_ref: fetch(normalized, :backend_ref),
         governed_command_ref: fetch(normalized, :command_ref),
         governed_credential_ref: fetch(normalized, :credential_ref),
         redaction_values: values
       ]}
    end
  end

  defp normalize_authority(authority) when is_map(authority), do: {:ok, authority}
  defp normalize_authority(authority) when is_list(authority), do: {:ok, Map.new(authority)}
  defp normalize_authority(_authority), do: {:error, :invalid_authority_packet}

  defp validate_required_refs(authority) do
    missing =
      @required_refs
      |> Enum.reject(fn key ->
        case fetch(authority, key) do
          value when is_binary(value) -> String.trim(value) != ""
          _ -> false
        end
      end)

    if missing == [] do
      :ok
    else
      {:error, {:missing_governed_refs, missing}}
    end
  end

  defp validate_known_ref(authority, key, allowed_refs) do
    ref = fetch(authority, key)

    if ref in allowed_refs do
      :ok
    else
      {:error, {:unknown_governed_ref, key, ref}}
    end
  end

  defp backend_for(authority) do
    ref = fetch(authority, :backend_ref)

    case BackendResolver.fetch_builtin_ref(ref) do
      {:ok, backend} -> {:ok, backend}
      :error -> {:error, {:unknown_governed_backend_ref, ref}}
    end
  end

  defp reject_direct_fields(opts) do
    hits =
      @direct_fields
      |> Enum.filter(&Keyword.has_key?(opts, &1))

    if hits == [] do
      :ok
    else
      {:error, {:direct_governed_config, hits}}
    end
  end

  defp reject_direct_cli_fields(opts) do
    hits =
      @direct_fields
      |> Enum.filter(&Keyword.has_key?(opts, &1))

    if hits == [] do
      :ok
    else
      {:error, {:direct_governed_config, hits}}
    end
  end

  defp required_binary(authority, key) do
    case fetch(authority, key) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value == "" do
          {:error, {:missing_governed_value, key}}
        else
          {:ok, value}
        end

      _ ->
        {:error, {:missing_governed_value, key}}
    end
  end

  defp optional_binary(authority, key, default) do
    case fetch(authority, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: default, else: value

      nil ->
        default

      value ->
        value
    end
  end

  defp optional_boolean(authority, key, default) do
    case fetch(authority, key) do
      value when is_boolean(value) -> value
      value when value in ["true", "TRUE", "True", "1", 1] -> true
      value when value in ["false", "FALSE", "False", "0", 0] -> false
      nil -> default
      _ -> default
    end
  end

  defp parse_bool(nil), do: nil
  defp parse_bool(value) when is_boolean(value), do: value
  defp parse_bool(value) when value in ["true", "TRUE", "True", "1", 1], do: true
  defp parse_bool(value) when value in ["false", "FALSE", "False", "0", 0], do: false
  defp parse_bool(value), do: value

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> value == nil end)
  end
end
