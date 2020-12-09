defmodule GlificWeb.Resolvers.Triggers do
  @moduledoc """
  Trigger Resolver which sits between the GraphQL schema and Glific Trigger Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.Triggers.Trigger

  @doc false
  @spec create_trigger(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_trigger(_, %{input: params}, _) do
    with {:ok, trigger} <- Trigger.create_trigger(params) do
      {:ok, %{trigger: trigger}}
    end
  end
end
