defmodule Glific.Groups.ContactWAGroups do
  @moduledoc """
  Simple container to hold all the contact groups we associate with one contact
  """

  alias Glific.{
    Contacts,
    Groups.ContactWAGroup,
    Groups.ContactWAGroups,
    Groups.WAGroup,
    Groups.WAGroups,
    Providers.Maytapi.ApiClient,
    Repo,
    SafeLog,
    WAGroup.WAManagedPhone
  }

  use Ecto.Schema
  import Ecto.Query, warn: false

  @primary_key false

  @type t() :: %__MODULE__{
          wa_group_contacts: [ContactWAGroup.t()],
          number_deleted: non_neg_integer
        }

  embedded_schema do
    # the number of contacts we deleted
    field(:number_deleted, :integer, default: 0)
    embeds_many(:wa_group_contacts, ContactWAGroup)
  end

  @doc """
  Returns the list of contact whatsapp groups structs.

  ## Examples

      iex> list_contact_wa_group()
      [%ContactWAGroup{}, ...]

  """
  @spec list_contact_wa_group(map()) :: [ContactWAGroup.t()]
  def list_contact_wa_group(args) do
    args
    |> Repo.list_filter_query(ContactWAGroup, &Repo.opts_with_id/2, &filter_with/2)
    |> Repo.all()
  end

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:wa_group_id, wa_group_id}, query ->
        where(query, [q], q.wa_group_id == ^wa_group_id)

      _, query ->
        query
    end)
  end

  @doc false
  @spec create_contact_wa_group(map()) :: {:ok, ContactWAGroup.t()} | {:error, Ecto.Changeset.t()}
  def create_contact_wa_group(attrs \\ %{}) do
    # check if an entry exists
    attrs = Map.take(attrs, [:contact_id, :wa_group_id, :organization_id, :is_admin])

    case Repo.fetch_by(ContactWAGroup, attrs) do
      {:ok, cg} ->
        {:ok, cg}

      {:error, _} ->
        %ContactWAGroup{}
        |> ContactWAGroup.changeset(attrs)
        |> Repo.insert()
    end
  end

  @doc false
  @spec update_contact_wa_groups(%{
          :add_wa_contact_ids => any(),
          :delete_wa_contact_ids => [integer()],
          :wa_group_id => integer(),
          optional(any()) => any()
        }) :: Glific.Groups.ContactWAGroups.t()

  def update_contact_wa_groups(
        %{
          wa_group_id: wa_group_id,
          add_wa_contact_ids: add_ids,
          delete_wa_contact_ids: delete_ids,
          organization_id: org_id
        } = attrs
      ) do
    wa_group_contacts =
      Enum.reduce(add_ids, [], fn add_id, acc ->
        {contact_id, is_admin} =
          case add_id do
            %{:contact_id => id, :is_admin => admin} ->
              {id, admin}

            _ when is_integer(add_id) or is_binary(add_id) ->
              {String.to_integer(to_string(add_id)), false}
          end

        attrs_with_contact_id_and_admin =
          Map.put(attrs, :contact_id, contact_id)
          |> Map.put(:is_admin, is_admin)

        case create_contact_wa_group(attrs_with_contact_id_and_admin) do
          {:ok, wa_group_contact} -> [wa_group_contact | acc]
          _ -> acc
        end
      end)

    number_deleted = remove_group_members(org_id, wa_group_id, delete_ids)

    %ContactWAGroups{
      number_deleted: number_deleted,
      wa_group_contacts: wa_group_contacts
    }
  end

  @doc false
  @spec delete_wa_group_contacts_by_ids(integer, list()) :: {integer(), nil | [term()]}
  def delete_wa_group_contacts_by_ids(wa_group_id, contact_ids) do
    fields = {{:wa_group_id, wa_group_id}, {:contact_id, contact_ids}}
    Repo.delete_relationships_by_ids(ContactWAGroup, fields)
  end

  @doc """
  Return the count of wa group contacts, using the same filter as list_wa_group_contacts
  """
  @spec count_contact_wa_group(map()) :: [ContactWAGroup.t()]
  def count_contact_wa_group(args) do
    args
    |> Repo.list_filter_query(ContactWAGroup, nil, &filter_with/2)
    |> Repo.aggregate(:count)
  end

  @spec remove_group_members(non_neg_integer(), non_neg_integer(), list()) ::
          integer()
  defp remove_group_members(org_id, wa_group_id, contact_ids) do
    wa_group = WAGroups.get_wa_group!(wa_group_id) |> Repo.preload(:primary_phone)

    Enum.reduce(contact_ids, 0, fn contact_id, numbers_deleted ->
      contact = Contacts.get_contact!(contact_id)
      payload = %{conversation_id: wa_group.bsp_id, number: contact.phone}

      case ApiClient.remove_group_member(org_id, payload, wa_group.primary_phone.phone_id) do
        :ok ->
          fields = {{:wa_group_id, wa_group_id}, {:contact_id, [contact_id]}}
          {number_deleted, _} = Repo.delete_relationships_by_ids(ContactWAGroup, fields)
          numbers_deleted + number_deleted

        {:error, _} ->
          numbers_deleted
      end
    end)
  end

  @doc """
  Add `phones` to a WhatsApp group via Maytapi, using `wa_managed_phone_id` as
  the acting phone for every Maytapi call. This is the entry point for the
  background CSV member import (`WAGroupMemberImportWorker`) — adding members is
  never a foreground/GraphQL action.

  Each phone is added with its own Maytapi `group/add` call, and its contact is
  created on the fly when we don't already have it; on success we insert the
  matching `contacts_wa_groups` row.

  Maytapi answers HTTP 200 even on failure (e.g.
  `%{"success" => false, "message" => "NOT_A_PARTICIPANT"}`), so we inspect the
  `success` field. A failed add fails only that number — it's collected in the
  returned `failed` map (`%{phone => message}`) so the caller can report it.

  `wa_managed_phone_id` is the acting phone; the caller resolves it via
  `WAGroups.acting_phone/1`.

  Returns `{:ok, %{added: n, failed: %{phone => message}}}`, or
  `{:error, message}` when the acting phone isn't in this organization.
  """
  @spec add_members(WAGroup.t(), non_neg_integer(), [String.t()]) ::
          {:ok, %{added: non_neg_integer(), failed: %{String.t() => String.t()}}}
          | {:error, String.t()}
  def add_members(_wa_group, _wa_managed_phone_id, []),
    do: {:ok, %{added: 0, failed: %{}}}

  def add_members(%WAGroup{} = wa_group, wa_managed_phone_id, phones) do
    with {:ok, acting_phone_id} <- acting_phone_id(wa_group, wa_managed_phone_id) do
      do_add_members(wa_group.organization_id, wa_group, acting_phone_id, phones)
    end
  end

  @doc """
  Remove the contact `remove_contact_id` from a WhatsApp group via Maytapi, using
  `wa_managed_phone_id` as the acting phone. This is the member action driven by
  the `updateWaGroup` mutation.

  On success the matching `contacts_wa_groups` row is deleted. A failed remove
  stops with `{:error, message}`; a `nil` contact id is a no-op.

  Returns `{:ok, count}`, or `{:error, message}` when the acting phone isn't in
  this organization or Maytapi rejects the removal.
  """
  @spec remove_member(WAGroup.t(), non_neg_integer(), non_neg_integer() | nil) ::
          {:ok, non_neg_integer()} | {:error, String.t()}
  def remove_member(_wa_group, _wa_managed_phone_id, nil), do: {:ok, 0}

  def remove_member(%WAGroup{} = wa_group, wa_managed_phone_id, contact_id) do
    with {:ok, acting_phone_id} <- acting_phone_id(wa_group, wa_managed_phone_id) do
      do_remove_member(wa_group.organization_id, wa_group, acting_phone_id, contact_id)
    end
  end

  # Resolve the acting managed phone (scoped to the group's org) to its Maytapi
  # `phone_id`, which every group/add and group/remove call is issued from.
  @spec acting_phone_id(WAGroup.t(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, String.t()}
  defp acting_phone_id(wa_group, wa_managed_phone_id) do
    case Repo.get_by(WAManagedPhone, %{
           id: wa_managed_phone_id,
           organization_id: wa_group.organization_id
         }) do
      nil -> {:error, "Acting phone not found in this organization"}
      %WAManagedPhone{phone_id: acting_phone_id} -> {:ok, acting_phone_id}
    end
  end

  @spec do_add_members(non_neg_integer(), WAGroup.t(), non_neg_integer(), [String.t()]) ::
          {:ok, %{added: non_neg_integer(), failed: %{String.t() => String.t()}}}
  defp do_add_members(org_id, wa_group, acting_phone_id, phones) do
    result =
      Enum.reduce(phones, %{added: 0, failed: %{}}, fn phone, acc ->
        payload = %{conversation_id: wa_group.bsp_id, number: [phone]}

        case ApiClient.add_group_member(org_id, payload, acting_phone_id) do
          :ok ->
            case link_phone_to_group(phone, wa_group, org_id) do
              {:ok, _} ->
                %{acc | added: acc.added + 1}

              {:error, reason} ->
                Glific.log_error(
                  "WA group add: phone #{phone} added on Maytapi but local link failed for wa_group=#{wa_group.id}: #{SafeLog.safe_inspect(reason)}"
                )

                %{
                  acc
                  | failed:
                      Map.put(
                        acc.failed,
                        phone,
                        "Added on WhatsApp but could not be linked in Glific"
                      )
                }
            end

          {:error, message} ->
            %{acc | failed: Map.put(acc.failed, phone, message)}
        end
      end)

    {:ok, result}
  end

  @spec link_phone_to_group(String.t(), WAGroup.t(), non_neg_integer()) ::
          {:ok, any()} | {:error, any()}
  defp link_phone_to_group(phone, wa_group, org_id) do
    with {:ok, contact} <-
           Contacts.maybe_create_contact(%{
             phone: phone,
             organization_id: org_id,
             contact_type: "WA"
           }) do
      create_contact_wa_group(%{
        contact_id: contact.id,
        wa_group_id: wa_group.id,
        organization_id: org_id,
        is_admin: false
      })
    end
  end

  @spec do_remove_member(non_neg_integer(), WAGroup.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, String.t()}
  defp do_remove_member(org_id, wa_group, acting_phone_id, contact_id) do
    contact = Contacts.get_contact!(contact_id)
    # /group/remove takes a single plain phone number (a string, not an array).
    payload = %{conversation_id: wa_group.bsp_id, number: contact.phone}

    case ApiClient.remove_group_member(org_id, payload, acting_phone_id) do
      :ok ->
        delete_wa_group_contacts_by_ids(wa_group.id, [contact_id])
        {:ok, 1}

      {:error, message} ->
        {:error, message}
    end
  end
end
