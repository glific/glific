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

  object :user_group_mutations do
    field :create_user_group, :user_group_result do
      arg(:input, non_null(:user_group_input))
      resolve(&Resolvers.Groups.create_user_group/3)
    end

    field :delete_user_group, :user_group_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Groups.delete_user_group/3)
    end
  end
end
