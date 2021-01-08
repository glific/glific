defmodule GlificWeb.Resolvers.Locations do
  @moduledoc """
  Location Resolver which sits between the GraphQL schema and Glific Location Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.Contacts.Location
  alias Glific.Repo

  @doc """
  Get a specific message media by id
  """
  @spec location(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def location(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, location} <-
           Repo.fetch_by(Location, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{location: location}}
  end

  @doc false
  @spec locations(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def locations(_, args, _) do
    {:ok, Repo.list_filter(args, Location, &Repo.opts_with_nil/2, &Repo.filter_with/2)}
  end
end
