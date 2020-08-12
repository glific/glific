defmodule Glific.Groups.GroupContacts do
  @moduledoc """
  Simple container to hold all the group contacts we associate with one group
  """

  alias __MODULE__

  alias Glific.{
    Groups,
    Groups.ContactGroup
  }

  use Ecto.Schema

  @primary_key false

  @type t() :: %__MODULE__{
          group_contacts: [ContactGroup.t()]
        }

  embedded_schema do
    # the number of contacts we deleted
    field :number_deleted, :integer
    embeds_many(:group_contacts, ContactGroup)
  end

  @doc """
  Creates and/or deletes a list of group contacts, each contact attached to the same group
  """
  @spec update_group_contacts(map()) :: GroupContacts.t()
  def update_group_contacts(
        %{group_id: group_id, add_contact_ids: add_ids, delete_contact_ids: delete_ids} = attrs
      ) do
    # we'll ignore errors intentionally here. the return list indicates
    # what objects we created
    group_contacts =
      Enum.reduce(
        add_ids,
        [],
        fn contact_id, acc ->
          case Groups.create_contact_group(Map.put(attrs, :contact_id, contact_id)) do
            {:ok, group_contact} -> [group_contact | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = Groups.delete_group_contacts_by_ids(group_id, delete_ids)

    %GroupContacts{
      number_deleted: number_deleted,
      group_contacts: group_contacts
    }
  end
end
