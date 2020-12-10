defmodule GlificWeb.Resolvers.Triggers do
  @moduledoc """
  Trigger Resolver which sits between the GraphQL schema and Glific Trigger Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.Repo

  alias Glific.Triggers.{
    Trigger,
    TriggerAction,
    TriggerCondition
  }

  @doc false
  @spec trigger(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def trigger(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, trigger} <-
           Repo.fetch_by(Trigger, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{trigger: trigger}}
  end

  @doc """
  Get the list of triggers filtered by args
  """
  @spec triggers(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [any]}
  def triggers(_, args, _) do
    {:ok, Trigger.list_triggers(args)}
  end

  @doc """
  Get the count of triggers filtered by args
  """
  @spec count_triggers(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_triggers(_, args, _) do
    {:ok, Trigger.count_triggers(args)}
  end

  @doc false
  @spec create_trigger(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_trigger(_, %{input: params}, _) do
    # here first we need to create trigger action and trigger condition
    with {:ok, trigger_action} <- TriggerAction.create_trigger_action(params),
         {:ok, trigger_condition} <- TriggerCondition.create_trigger_condition(params),
         {:ok, trigger} <-
           Trigger.create_trigger(
             params
             |> Map.merge(%{
               trigger_action_id: trigger_action.id,
               trigger_condition_id: trigger_condition.id
             })
           ) do
      {:ok, %{trigger: trigger}}
    end
  end

  @doc """
  Update a trigger
  """
  @spec update_trigger(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_trigger(_, %{id: id, input: params}, _) do
    with {:ok, trigger} <- Repo.fetch(Trigger, id) do
      trigger = Repo.preload(trigger, [:trigger_action, :trigger_condition])
      {:ok, _} = TriggerAction.update_trigger_action(trigger.trigger_action, params)
      {:ok, _} = TriggerCondition.update_trigger_condition(trigger.trigger_condition, params)
      {:ok, %{trigger: trigger}}
    end
  end
end
