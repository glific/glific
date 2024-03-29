defmodule Glific.Groups.ContactWAGroups do
  @moduledoc """
  Simple container to hold all the contact groups we associate with one contact
  """

  alias Glific.{
    Contacts,
    Groups.ContactWAGroup,
    Groups.ContactWAGroups,
    Groups.WAGroups,
    Providers.Maytapi.ApiClient,
    Repo
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
    wa_group = WAGroups.get_wa_group!(wa_group_id)
    wa_group = Repo.preload(wa_group, :wa_managed_phone)

    Enum.reduce(contact_ids, 0, fn contact_id, numbers_deleted ->
      contact = Contacts.get_contact!(contact_id)
      payload = %{conversation_id: wa_group.bsp_id, number: contact.phone <> "@c.us"}

      case ApiClient.remove_group_member(org_id, payload, wa_group.wa_managed_phone.phone_id) do
        {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
          fields = {{:wa_group_id, wa_group_id}, {:contact_id, [contact_id]}}
          {number_deleted, _} = Repo.delete_relationships_by_ids(ContactWAGroup, fields)
          numbers_deleted + number_deleted

        _ ->
          numbers_deleted
      end
    end)
  end
end
