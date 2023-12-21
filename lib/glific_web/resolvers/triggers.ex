defmodule GlificWeb.Resolvers.Triggers do
  @moduledoc """
  Trigger Resolver which sits between the GraphQL schema and Glific Trigger Context API.
  This layer basically stitches together one or more calls to resolve the incoming queries.
  """
  import GlificWeb.Gettext

  alias Glific.{Repo, Triggers, Triggers.Trigger}
  require Logger

  @doc false
  @spec trigger(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def trigger(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, trigger} <-
           Repo.fetch_by(Trigger, %{id: id, organization_id: user.organization_id}) do
      trigger
      |> Triggers.append_group_labels()
      |> then(&{:ok, %{trigger: &1}})
    end
  end

  @doc """
  Get the list of triggers filtered by args
  """
  @spec triggers(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [any]}
  def triggers(_, args, _) do
    {:ok, Triggers.list_triggers(args)}
  end

  @doc """
  Get the count of triggers filtered by args
  """
  @spec count_triggers(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_triggers(_, args, _) do
    {:ok, Triggers.count_triggers(args)}
  end

  @doc false
  @spec create_trigger(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_trigger(_, %{input: params}, _) do
    # here first we need to create trigger action and trigger condition
    with {:ok, trigger} <- Triggers.create_trigger(params) do
      {:ok, %{trigger: trigger}}
    end
  end

  @doc false
  @spec check_trigger_warnings(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def check_trigger_warnings(_, %{input: params}, _) do
    with {:ok, _} <- Triggers.check_trigger_warnings(params) do
      {:ok, %{errors: nil}}
    else
      {:warning, warning} ->
        {:ok, %{errors: [%{key: "warning", message: warning}]}}
    end
  end

  @doc """
  Update a trigger
  """
  @spec update_trigger(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_trigger(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, trigger} <-
           Repo.fetch_by(Trigger, %{id: id, organization_id: user.organization_id}),
         {:ok, cleaned_params} <- validate_params(params),
         {:ok, trigger} <- Triggers.update_trigger(trigger, cleaned_params) do
      {:ok, %{trigger: trigger}}
    else
      _ ->
        {:error,
         dgettext("errors", "Trigger start_at should always be greater than current time")}
    end
  end

  @spec validate_params(map()) :: {:ok, map()} | {:error, String.t()}
  defp validate_params(params) do
    param_keys = Map.keys(params)

    if Enum.any?(param_keys, fn param_key -> param_key in [:is_active] end) do
      {:error, "Cannot modify read-only fields"}
    else
      {:ok, params}
    end
  end

  @doc false
  @spec delete_trigger(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_trigger(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, trigger} <-
           Repo.fetch_by(Trigger, %{id: id, organization_id: user.organization_id}) do
      Logger.info(
        "Trigger for org_id: #{user.organization_id} has been deleted by #{user.name} phone: #{user.phone}"
      )

      Triggers.delete_trigger(trigger)
    end
  end
end
