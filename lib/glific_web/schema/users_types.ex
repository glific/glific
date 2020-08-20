defmodule GlificWeb.Schema.UserTypes do
  @moduledoc """
  GraphQL Representation of Glific's User DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias Glific.Users.User
  alias GlificWeb.Resolvers

  object :user_result do
    field :user, :user
    field :errors, list_of(:input_error)
  end

  object :user do
    field :id, :id
    field :name, :string
    field :phone, :string
    field :roles, list_of(:role)

    field :contact, :contact do
      resolve(dataloader(Repo))
    end

    field :groups, list_of(:group) do
      resolve(dataloader(Repo))
    end
  end

  object :role do
    field :id, :id
    field :label, :string
  end

  @desc "Filtering options for users"
  input_object :user_filter do
    @desc "Match the name"
    field :name, :string

    @desc "Match the phone"
    field :phone, :string
  end

  input_object :current_user_input do
    field :name, :string
    field :password, :string
    field :otp, :string
  end

  input_object :user_input do
    field :name, :string
    field :roles, list_of(:string)
    field :group_ids, non_null(list_of(:id))
  end

  object :user_queries do
    @desc "get list of roles"
    field :roles, list_of(:role) do
      resolve(fn _, _, _ ->
        {:ok, User.get_roles_list()}
      end)
    end

    @desc "get the details of one user"
    field :user, :user_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Users.user/3)
    end

    @desc "Get a list of all users filtered by various criteria"
    field :users, list_of(:user) do
      arg(:filter, :user_filter)
      arg(:opts, :opts)
      resolve(&Resolvers.Users.users/3)
    end

    @desc "Get a count of all users filtered by various criteria"
    field :count_users, :integer do
      arg(:filter, :user_filter)
      resolve(&Resolvers.Users.count_users/3)
    end
  end

  object :user_mutations do
    field :update_current_user, :user_result do
      arg(:id, non_null(:id))
      arg(:input, non_null(:current_user_input))
      resolve(&Resolvers.Users.update_current_user/3)
    end

    field :delete_user, :user_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Users.delete_user/3)
    end

    field :update_user, :user_result do
      arg(:id, non_null(:id))
      arg(:input, non_null(:user_input))
      resolve(&Resolvers.Users.update_user/3)
    end
  end
end
