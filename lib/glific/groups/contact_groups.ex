defmodule Glific.Groups.ContactGroups do
  @moduledoc """
  Simple container to hold all the contact groups we associate with one contact
  """

  alias __MODULE__

  alias Glific.{
    Groups,
    Groups.ContactGroup
  }

  use Ecto.Schema

  @primary_key false

  @type t() :: %__MODULE__{
          contact_groups: [ContactGroup.t()]
        }

  embedded_schema do
    # the number of contacts we deleted
    field :number_deleted, :integer
    embeds_many(:contact_groups, ContactGroup)
  end

  @doc """
  Creates and/or deletes a list of contact groups, each group attached to the same contact
  """
  @spec update_contact_groups(map()) :: ContactGroups.t()
  def update_contact_groups(
        %{contact_id: contact_id, add_group_ids: add_ids, delete_group_ids: delete_ids} = attrs
      ) do
    # we'll ignore errors intentionally here. the return list indicates
    # what objects we created
    contact_groups =
      Enum.reduce(
        add_ids,
        [],
        fn group_id, acc ->
          case Groups.create_contact_group(Map.put(attrs, :group_id, group_id)) do
            {:ok, contact_group} -> [contact_group | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = Groups.delete_contact_groups_by_ids(contact_id, delete_ids)

    %ContactGroups{
      number_deleted: number_deleted,
      contact_groups: contact_groups
    }
  end
end
