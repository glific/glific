defmodule GlificWeb.Schema.UserGroupTypes do
  @moduledoc """
  GraphQL Representation of Glific's User Group DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers

  object :user_group_result do
    field :user_group, :user_group
    field :errors, list_of(:input_error)
  end

  object :user_group do
    field :id, :id

    field :value, :string

    field :user, :user do
      resolve(dataloader(Repo))
    end

    field :group, :group do
      resolve(dataloader(Repo))
    end
  end

  input_object :user_group_input do
    field :user_id, :id
    field :group_id, :id
  end

  input_object :group_users_input do
    field :group_id, non_null(:id)
    field :add_user_ids, non_null(list_of(:id))
    field :delete_user_ids, non_null(list_of(:id))
  end

  object :group_users do
    field :number_deleted, :integer
    field :group_users, list_of(:user_group)
  end

  object :user_group_mutations do
    field :create_user_group, :user_group_result do
      arg(:input, non_null(:user_group_input))
      resolve(&Resolvers.Groups.create_user_group/3)
    end

    field :update_group_users, :group_users do
      arg(:input, non_null(:group_users_input))
      resolve(&Resolvers.Groups.update_group_users/3)
    end

    field :delete_user_group, :user_group_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Groups.delete_user_group/3)
    end
  end
end
