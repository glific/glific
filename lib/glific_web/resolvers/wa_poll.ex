defmodule GlificWeb.Resolvers.WaPoll do
  @moduledoc """
  WAPoll Resolver which sits between the GraphQL schema and Glific WAPollContext API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.WaPoll

  @doc """
  Get a specific whatsapp poll by id
  """
  @spec wa_poll(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def wa_poll(_, %{id: id}, _) do
    with {:ok, wa_poll} <-
           WaPoll.fetch_wa_poll(id),
         do: {:ok, %{wa_poll: wa_poll}}
  end

  @doc """
  Get the list of session Interactives filtered by args
  """
  @spec wa_polls(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def wa_polls(_, args, _) do
    {:ok, WaPoll.list_wa_polls(args)}
  end

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
