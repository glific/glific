defmodule GlificWeb.Resolvers.Contacts do
  @moduledoc """
  Contact Resolver which sits between the GraphQL schema and Glific Contact Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Contacts, Contacts.Contact, Repo}
  alias GlificWeb.Resolvers.Helper

  @doc false
  @spec contact(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def contact(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{contact: contact}}
  end

  @doc false
  @spec contacts(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [any]}
  def contacts(_, args, context) do
    {:ok, Contacts.list_contacts(Helper.add_org_filter(args, context))}
  end

  @doc """
  Get the count of contacts filtered by args
  """
  @spec count_contacts(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_contacts(_, args, context) do
    {:ok, Contacts.count_contacts(Helper.add_org_filter(args, context))}
  end

  @doc false
  @spec create_contact(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_contact(_, %{input: params}, _) do
    with {:ok, contact} <- Contacts.create_contact(params) do
      {:ok, %{contact: contact}}
    end
  end

  @doc false
  @spec update_contact(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_contact(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: id, organization_id: user.organization_id}),
         {:ok, contact} <- Contacts.update_contact(contact, params) do
      {:ok, %{contact: contact}}
    end
  end

  @doc false
  @spec delete_contact(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_contact(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: id, organization_id: user.organization_id}),
         {:ok, contact} <- Contacts.delete_contact(contact) do
      {:ok, contact}
    end
  end

  @doc """
  Get current location of the contact
  """
  @spec contact_location(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def contact_location(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: id, organization_id: user.organization_id}),
         {:ok, location} <- Contacts.contact_location(contact) do
      {:ok, location}
    end
  end
end
