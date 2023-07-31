defmodule GlificWeb.Resolvers.ContactsField do
  @moduledoc """
  Contact Field Resolver which sits between the GraphQL schema and Glific Contact Field Context API.
  """
  alias Glific.{Contacts.ContactsField, Flows.ContactField, Repo}

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

  @doc """
  Get the list of contacts_fields filtered by args
  """
  @spec contacts_fields(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [ContactsField]}
  def contacts_fields(_, args, _) do
    {:ok, ContactField.list_contacts_fields(args)}
  end

  @doc """
  Get the count of contacts_fields filtered by args
  """
  @spec count_contacts_fields(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_contacts_fields(_, args, _) do
    {:ok, ContactField.count_contacts_fields(args)}
  end

  @doc """
  Create contact field
  """
  @spec create_contacts_field(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_contacts_field(_, %{input: params}, _) do
    with {:ok, contacts_field} <- ContactField.create_contact_field(params) do
      {:ok, %{contacts_field: contacts_field}}
    end
  end

  @doc """
  Update existing contact field
  """
  @spec update_contacts_field(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_contacts_field(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, contacts_field} <-
           Repo.fetch_by(ContactsField, %{id: id, organization_id: user.organization_id}),
         {:ok, contacts_field} <- ContactField.update_contacts_field(contacts_field, params) do
      {:ok, %{contacts_field: contacts_field}}
    end
  end

  @doc """
  Merge two contact fields
  """
  @spec merge_contacts_fields(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def merge_contacts_fields(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, contacts_field} <-
           Repo.fetch_by(ContactsField, %{id: id, organization_id: user.organization_id}),
         {:ok, contacts_field} <- ContactField.merge_contacts_fields(contacts_field, params) do
      {:ok, %{contacts_field: contacts_field}}
    end
  end

  @doc """
  Delete an existing contact field
  """
  @spec delete_contacts_field(Absinthe.Resolution.t(), %{id: integer, delete_assoc: boolean()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def delete_contacts_field(_, %{id: id, delete_assoc: delete_assoc}, %{
        context: %{current_user: user}
      }) do
    with {:ok, contacts_field} <-
           Repo.fetch_by(ContactsField, %{id: id, organization_id: user.organization_id}) do
      ContactField.delete_contacts_field(contacts_field, delete_assoc)
    end
  end
end
