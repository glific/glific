defmodule GlificWeb.Resolvers.WaGroup do
  @moduledoc """
  Group Resolver which sits between the GraphQL schema and Glific Group Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    Groups.ContactWAGroups,
    Groups.WAGroups
  }

  @doc """
  Get the list of contact whastapp groups filtered by args
  """
  @spec list_contact_wa_group(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def list_contact_wa_group(_, args, _) do
    {:ok, ContactWAGroups.list_contact_wa_group(args)}
  end

  @doc """
  Creates an contact whatsapp group entry
  """
  @spec create_contact_wa_group(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_contact_wa_group(_, %{input: params}, _) do
    with {:ok, contact_wa_group} <- ContactWAGroups.create_contact_wa_group(params) do
      {:ok, %{contact_wa_group: contact_wa_group}}
    end
  end

  @doc false
  @spec update_contact_wa_groups(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_contact_wa_groups(_, %{input: params}, _) do
    contact_wa_group = ContactWAGroups.update_contact_wa_groups(params)
    {:ok, contact_wa_group}
  end

  @doc false

  @spec sync_contact_wa_groups(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def sync_contact_wa_groups(_, _, %{context: %{current_user: user}}) do
    case WAGroups.fetch_wa_groups(user.organization_id) do
      :ok -> {:ok, %{message: "successfully synced"}}
    end
  end

  @doc """
  Get the count of contact whastapp groups filtered by args
  """
  @spec count_contact_wa_group(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def count_contact_wa_group(_, args, _) do
    {:ok, ContactWAGroups.count_contact_wa_group(args)}
  end
end
