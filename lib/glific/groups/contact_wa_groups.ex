defmodule Glific.Groups.ContactWaGroups do
  @moduledoc """
  Simple container to hold all the contact groups we associate with one contact
  """

  alias Glific.{
    Groups.ContactWAGroup,
    Groups.ContactWaGroups,
    Repo
  }

  use Ecto.Schema
  import Ecto.Query, warn: false

  @primary_key false

  @type t() :: %__MODULE__{
          contact_wa_groups: [ContactWAGroup.t()],
          wa_group_contacts: [ContactWAGroup.t()],
          number_deleted: non_neg_integer
        }

  embedded_schema do
    # the number of contacts we deleted
    field(:number_deleted, :integer, default: 0)
    embeds_many(:contact_wa_groups, ContactWAGroup)
    embeds_many(:wa_group_contacts, ContactWAGroup)
  end

  @doc """
  Returns the list of contact whatsapp groups structs.

  ## Examples

      iex> list_contact_groups()
      [%ContactWAGroup{}, ...]

  """
  @spec list_contact_groups(map()) :: [ContactWAGroup.t()]
  def list_contact_groups(args) do
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

      {:contact_id, contact_id}, query ->
        where(query, [q], q.contact_id == ^contact_id)

      _, query ->
        query
    end)
  end

  @spec create_contact_wa_group(map()) :: {:ok, ContactWAGroup.t()} | {:error, Ecto.Changeset.t()}
  def create_contact_wa_group(attrs \\ %{}) do
    # check if an entry exists
    attrs = Map.take(attrs, [:contact_id, :wa_group_id, :organization_id])

    case Repo.fetch_by(ContactWAGroup, attrs) do
      {:ok, cg} ->
        {:ok, cg}

      {:error, _} ->
        %ContactWAGroup{}
        |> ContactWAGroup.changeset(attrs)
        |> Repo.insert()
    end
  end

  @spec update_wa_group_contacts(%{
          :add_wa_contact_ids => any(),
          :delete_wa_contact_ids => [integer()],
          :wa_group_id => integer(),
          optional(any()) => any()
        }) :: Glific.Groups.ContactWaGroups.t()
  def update_wa_group_contacts(
        %{
          wa_group_id: wa_group_id,
          add_wa_contact_ids: add_ids,
          delete_wa_contact_ids: delete_ids
        } =
          attrs
      ) do
    # we'll ignore errors intentionally here. the return list indicates
    # what objects we created
    wa_group_contacts =
      Enum.reduce(
        add_ids,
        [],
        fn contact_id, acc ->
          case create_contact_wa_group(Map.put(attrs, :contact_id, contact_id)) do
            {:ok, wa_group_contact} -> [wa_group_contact | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = delete_wa_group_contacts_by_ids(wa_group_id, delete_ids)

    %ContactWaGroups{
      number_deleted: number_deleted,
      wa_group_contacts: wa_group_contacts
    }
  end

  @spec delete_wa_group_contacts_by_ids(integer, list()) :: {integer(), nil | [term()]}
  def delete_wa_group_contacts_by_ids(wa_group_id, contact_ids) do
    fields = {{:wa_group_id, wa_group_id}, {:contact_id, contact_ids}}
    Repo.delete_relationships_by_ids(ContactWAGroup, fields)
  end
end
