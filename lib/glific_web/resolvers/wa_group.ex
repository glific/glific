defmodule GlificWeb.Resolvers.WaGroup do
  @moduledoc """
  Group Resolver which sits between the GraphQL schema and Glific Group Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """
  use Gettext, backend: GlificWeb.Gettext

  alias Glific.{
    Groups.ContactWAGroups,
    Groups.WAGroup,
    Groups.WAGroups,
    WAGroup.WAManagedPhone
  }

  @doc """
  Get a specific WhatsApp group by id
  """
  @spec wa_group(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def wa_group(_, %{id: id}, _context) do
    {:ok, %{wa_group: WAGroups.get_wa_group!(id)}}
  rescue
    _ -> {:error, ["WAGroup", dgettext("errors", "WAGroup not found or permission denied.")]}
  end

  @doc """
  Get the list of WhatsApp groups filtered by args
  """
  @spec wa_groups(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def wa_groups(_, args, _), do: {:ok, WAGroups.wa_groups(args)}

  @doc """
  Get the list of contact WhatsApp groups filtered by args
  """
  @spec list_contact_wa_group(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def list_contact_wa_group(_, args, _), do: {:ok, ContactWAGroups.list_contact_wa_group(args)}

  @doc """
  Creates an contact WhatsApp group entry
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
  @spec sync_wa_group_contacts(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def sync_wa_group_contacts(_, _, %{context: %{current_user: user}}) do
    case WAGroups.sync_wa_groups(user.organization_id) do
      :ok -> {:ok, %{message: "successfully synced"}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the count of contact WhatsApp groups filtered by args
  """
  @spec count_contact_wa_group(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def count_contact_wa_group(_, args, _), do: {:ok, ContactWAGroups.count_contact_wa_group(args)}

  @doc """
  Get the list of WhatsApp groups filtered by args
  """
  @spec wa_groups_count(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def wa_groups_count(_, args, _), do: {:ok, WAGroups.wa_groups_count(args)}

  @doc """
  Resolve `WAGroup.primaryPhone` — the managed phone whose membership row
  has `is_primary: true` and `is_active: true`.
  """
  @spec primary_phone(WAGroup.t(), map(), %{context: map()}) ::
          {:ok, WAManagedPhone.t() | nil}
  def primary_phone(wa_group, _args, _resolution) do
    {:ok, WAGroups.primary_phone(wa_group.id)}
  end

  @doc """
  Promote a managed phone to the group's primary. Admin-only.
  """
  @spec set_primary_phone(
          Absinthe.Resolution.t(),
          %{wa_group_id: integer, wa_managed_phone_id: integer},
          %{
            context: map()
          }
        ) :: {:ok, any} | {:error, any}
  def set_primary_phone(_, args, _) do
    %{wa_group_id: wa_group_id, wa_managed_phone_id: wa_managed_phone_id} = args

    case WAGroups.set_primary_phone(wa_group_id, wa_managed_phone_id) do
      {:ok, result} ->
        Appsignal.increment_counter("glific.maytapi.primary_changed", 1, %{source: "manual"})
        {:ok, result}

      {:error, :membership_not_found} ->
        {:error,
         dgettext(
           "errors",
           "This phone is not a member of the group. Add it to the group on WhatsApp before promoting."
         )}

      {:error, :inactive_membership} ->
        {:error,
         dgettext(
           "errors",
           "This phone was removed from the group. Re-add it on WhatsApp before promoting."
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end
end
