defmodule Glific.Groups.UserGroups do
  @moduledoc """
  Simple container to hold all the user groups we associate with one user
  """

  alias __MODULE__

  alias Glific.{
    Groups,
    Groups.UserGroup
  }

  use Ecto.Schema

  @primary_key false

  @type t() :: %__MODULE__{
          user_groups: [UserGroup.t()]
        }

  embedded_schema do
    # the number of users we deleted
    field :number_deleted, :integer
    embeds_many(:user_groups, UserGroup)
  end

  @doc """
  Creates and/or deletes a list of user groups, each group attached to the same user
  """
  @spec update_user_groups(map()) :: UserGroups.t()
  def update_user_groups(
        %{user_id: user_id, add_group_ids: add_ids, delete_group_ids: delete_ids} = attrs
      ) do
    # we'll ignore errors intentionally here. the return list indicates
    # what objects we created
    user_groups =
      Enum.reduce(
        add_ids,
        [],
        fn group_id, acc ->
          case Groups.create_user_group(Map.put(attrs, :group_id, group_id)) do
            {:ok, user_group} -> [user_group | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = Groups.delete_user_groups_by_ids(user_id, delete_ids)

    %UserGroups{
      number_deleted: number_deleted,
      user_groups: user_groups
    }
  end
end
