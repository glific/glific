defmodule Glific.Groups.GroupUsers do
  @moduledoc """
  Simple container to hold all the group users we associate with one group
  """

  alias __MODULE__

  alias Glific.{
    Groups,
    Groups.UserGroup
  }

  use Ecto.Schema

  @primary_key false

  @type t() :: %__MODULE__{
          group_users: [UserGroup.t()]
        }

  embedded_schema do
    # the number of users we deleted
    field :number_deleted, :integer
    embeds_many(:group_users, UserGroup)
  end

  @doc """
  Creates and/or deletes a list of group users, each user attached to the same group
  """
  @spec update_group_users(map()) :: GroupUsers.t()
  def update_group_users(
        %{group_id: group_id, add_user_ids: add_ids, delete_user_ids: delete_ids} = attrs
      ) do
    # we'll ignore errors intentionally here. the return list indicates
    # what objects we created
    group_users =
      Enum.reduce(
        add_ids,
        [],
        fn user_id, acc ->
          case Groups.create_user_group(Map.put(attrs, :user_id, user_id)) do
            {:ok, group_user} -> [group_user | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = Groups.delete_group_users_by_ids(group_id, delete_ids)

    %GroupUsers{
      number_deleted: number_deleted,
      group_users: group_users
    }
  end
end
