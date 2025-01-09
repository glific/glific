defmodule GlificWeb.Resolvers.WaPoll do
  @moduledoc """
  WAPoll Resolver which sits between the GraphQL schema and Glific WAPollContext API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.WaPoll

  @doc false
  @spec create_wa_poll(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_wa_poll(_, %{input: params}, _) do
    with {:ok, wa_poll} <-
           WaPoll.create_wa_poll(params) do
      {:ok, %{wa_poll: wa_poll}}
    end
  end
end
