defmodule GlificWeb.Resolvers.Guardrails do
  @moduledoc """
  Resolvers for Kaapi guardrail validator configs. Kaapi owns the configs and scopes them by
  the organization's Kaapi API key, so nothing is stored in Glific.
  """

  alias Glific.ThirdParty.Kaapi

  @non_config_keys [
    :id,
    :name,
    :type,
    :stage,
    :on_fail_action,
    :is_enabled,
    :organization_id,
    :project_id,
    :inserted_at,
    :updated_at
  ]

  @unknown_error "An unknown error occurred, please contact Glific support."

  @doc """
  List the guardrail validator types supported by Kaapi along with their config JSON schemas.
  """
  @spec list_guardrail_validators(map(), map(), map()) :: {:ok, map()}
  def list_guardrail_validators(_, _, %{context: %{current_user: user}}) do
    case Kaapi.list_guardrail_validators(user.organization_id) do
      {:ok, %{validators: validators}} -> {:ok, %{validators: validators}}
      result -> error_result(result)
    end
  end

  @doc """
  List the organization's guardrail validator configs, optionally filtered by ids, stage and type.
  """
  @spec list_guardrail_configs(map(), map(), map()) :: {:ok, map()}
  def list_guardrail_configs(_, args, %{context: %{current_user: user}}) do
    args
    |> Map.get(:filter, %{})
    |> list_query()
    |> Kaapi.list_guardrail_configs(user.organization_id)
    |> case do
      {:ok, %{data: configs}} when is_list(configs) ->
        {:ok, %{guardrail_configs: Enum.map(configs, &with_config/1)}}

      result ->
        error_result(result)
    end
  end

  @doc """
  Get a guardrail validator config.
  """
  @spec get_guardrail_config(map(), map(), map()) :: {:ok, map()}
  def get_guardrail_config(_, %{id: id}, %{context: %{current_user: user}}) do
    with_config_id(id, fn config_id ->
      config_id
      |> Kaapi.get_guardrail_config(user.organization_id)
      |> config_result()
    end)
  end

  @doc """
  Create a guardrail validator config. Validator-specific `config` keys are sent alongside the
  base fields, as Kaapi expects a flat body.
  """
  @spec create_guardrail_config(map(), map(), map()) :: {:ok, map()}
  def create_guardrail_config(_, %{input: input}, %{context: %{current_user: user}}) do
    case Map.get(input, :config) || %{} do
      config when is_map(config) ->
        base_fields =
          input
          |> base_fields()
          |> Map.new(fn {key, value} -> {"#{key}", value} end)

        config
        |> Map.merge(base_fields)
        |> Kaapi.create_guardrail_config(user.organization_id)
        |> config_result()

      _ ->
        errors("config must be a JSON object")
    end
  end

  @doc """
  Update a guardrail validator config. Kaapi only allows the base fields to be updated.
  """
  @spec update_guardrail_config(map(), map(), map()) :: {:ok, map()}
  def update_guardrail_config(_, %{id: id, input: input}, %{context: %{current_user: user}}) do
    with_config_id(id, fn config_id ->
      config_id
      |> Kaapi.update_guardrail_config(base_fields(input), user.organization_id)
      |> config_result()
    end)
  end

  @doc """
  Delete a guardrail validator config.
  """
  @spec delete_guardrail_config(map(), map(), map()) :: {:ok, map()}
  def delete_guardrail_config(_, %{id: id}, %{context: %{current_user: user}}) do
    with_config_id(id, fn config_id ->
      case Kaapi.delete_guardrail_config(config_id, user.organization_id) do
        {:ok, %{success: true}} -> {:ok, %{guardrail_config: %{id: config_id}}}
        result -> error_result(result)
      end
    end)
  end

  # AddOrganization puts organization_id into every input, but Kaapi rejects it: the tenant
  # comes from the API key
  @spec base_fields(map()) :: map()
  defp base_fields(input), do: Map.drop(input, [:config, :organization_id])

  @spec list_query(map()) :: Keyword.t()
  defp list_query(filter) do
    Enum.flat_map(filter, fn
      {_key, nil} -> []
      # Kaapi (FastAPI) reads repeated `ids=` params; Tesla would encode a list as `ids[]=`
      {:ids, ids} -> Enum.map(ids, &{:ids, &1})
      {key, value} -> [{key, value}]
    end)
  end

  @spec with_config_id(String.t(), (String.t() -> {:ok, map()})) :: {:ok, map()}
  defp with_config_id(id, request) do
    case Ecto.UUID.cast(id) do
      {:ok, config_id} -> request.(config_id)
      :error -> errors("Invalid guardrail config id.")
    end
  end

  @spec config_result({:ok | :error, any()}) :: {:ok, map()}
  defp config_result({:ok, %{data: %{} = config}}),
    do: {:ok, %{guardrail_config: with_config(config)}}

  defp config_result(result), do: error_result(result)

  @spec with_config(map()) :: map()
  defp with_config(config), do: Map.put(config, :config, Map.drop(config, @non_config_keys))

  @spec error_result({:ok | :error, any()}) :: {:ok, map()}
  defp error_result({:ok, %{error: error}}) when is_binary(error), do: errors(error)
  defp error_result({:ok, _}), do: errors(@unknown_error)
  defp error_result({:error, reason}), do: errors(error_message(reason))

  @spec error_message(any()) :: String.t()
  defp error_message(:timeout), do: "Timeout occurred, please try again."
  defp error_message(%{body: %{error: error}}) when is_binary(error), do: error
  defp error_message(%{body: %{detail: detail}}) when is_binary(detail), do: detail

  defp error_message(%{body: %{detail: [_ | _] = details}}),
    do: Enum.map_join(details, "; ", &validation_message/1)

  defp error_message(%{status: 404}), do: "Guardrail config not found."
  defp error_message(message) when is_binary(message), do: message
  defp error_message(_), do: @unknown_error

  @spec validation_message(map()) :: String.t()
  defp validation_message(%{loc: [_ | _] = loc, msg: msg}), do: "#{List.last(loc)}: #{msg}"
  defp validation_message(%{msg: msg}), do: msg
  defp validation_message(_), do: @unknown_error

  @spec errors(String.t()) :: {:ok, map()}
  defp errors(message), do: {:ok, %{errors: [%{message: message}]}}
end
