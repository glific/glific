defmodule GlificWeb.Resolvers.Triggers do
  @moduledoc """
  Trigger Resolver which sits between the GraphQL schema and Glific Trigger Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.Triggers.{
    Trigger,
    TriggerAction,
    TriggerCondition
  }

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
end
