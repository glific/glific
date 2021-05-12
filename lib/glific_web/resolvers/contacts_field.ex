defmodule GlificWeb.Resolvers.ContactsField do
  @moduledoc """
  Contact Field Resolver which sits between the GraphQL schema and Glific Contact Field Context API.
  """
  alias Glific.{Contacts.ContactsField, Repo}

  @doc """
  Get a specific contact field by id
  """
  @spec contacts_field(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def contacts_field(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, contacts_field} <-
           Repo.fetch_by(ContactsField, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{contacts_field: contacts_field}}
  end
end
