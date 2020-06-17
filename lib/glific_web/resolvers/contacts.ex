defmodule GlificWeb.Resolvers.Contacts do
  @moduledoc """
  Contact Resolver which sits between the GraphQL schema and Glific Contact Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Contacts, Contacts.Contact, Repo}

  @doc false
  @spec contact(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def contact(_, %{id: id}, _) do
    with {:ok, contact} <- Repo.fetch(Contact, id),
         do: {:ok, %{contact: contact}}
  end

  @doc false
  @spec contacts(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, [any]}
  def contacts(_, args, _) do
    {:ok, Contacts.list_contacts(args)}
  end

  @doc """
  Get the count of contacts filtered by args
  """
  @spec count_contacts(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_contacts(_, args, _) do
    {:ok, Contacts.count_contacts(args)}
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
  def update_contact(_, %{id: id, input: params}, _) do
    with {:ok, contact} <- Repo.fetch(Contact, id),
         {:ok, contact} <- Contacts.update_contact(contact, params) do
      {:ok, %{contact: contact}}
    end
  end

  @doc false
  @spec delete_contact(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_contact(_, %{id: id}, _) do
    with {:ok, contact} <- Repo.fetch(Contact, id),
         {:ok, contact} <- Contacts.delete_contact(contact) do
      {:ok, contact}
    end
  end

  @doc false
  @spec search(Absinthe.Resolution.t(), %{term: String.t()}, %{context: map()}) ::
          {:ok, [any]}
  def search(_, %{term: term}, _) do
    {:ok, Contacts.search(term)}
  end
end
