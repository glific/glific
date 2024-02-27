defmodule GlificWeb.Resolvers.WaGroup do
  @moduledoc """
  Group Resolver which sits between the GraphQL schema and Glific Group Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.Groups.ContactWaGroups

  @doc """
  Get the list of contact whastapp groups filtered by args
  """
  @spec contact_wa_groups(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def contact_wa_groups(_, args, _) do
    {:ok, ContactWaGroups.list_contact_groups(args)}
  end

  @doc """
  Creates an contact whatsapp group entry
  """
  @spec create_contact_wa_group(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_contact_wa_group(_, %{input: params}, _) do
    with {:ok, contact_wa_group} <- ContactWaGroups.create_contact_wa_group(params) do
      {:ok, %{contact_group: contact_wa_group}}
    end
  end

  @doc false
  @spec update_wa_group_contacts(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_wa_group_contacts(_, %{input: params}, _) do
    wa_group_contacts = ContactWaGroups.update_wa_group_contacts(params)
    {:ok, wa_group_contacts}
  end
end
