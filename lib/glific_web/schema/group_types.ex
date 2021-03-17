defmodule GlificWeb.Schema.GroupTypes do
  @moduledoc """
  GraphQL Representation of Glific's Group DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :group_result do
    field :group, :group
    field :errors, list_of(:input_error)
  end

  object :group do
    field :id, :id
    field :label, :string
    field :description, :string
    field :is_restricted, :boolean

    field :last_communication_at, :datetime

    field :contacts, list_of(:contact) do
      resolve(dataloader(Repo))
    end

    field :users, list_of(:user) do
      resolve(dataloader(Repo))
    end

    field :messages, list_of(:message) do
      resolve(dataloader(Repo))
    end

    # number of contacts in the group
    # this is an expensive operation we can come back and optimise it later
    field :contacts_count, :integer do
      resolve(fn group, resolution, context ->
        Resolvers.Groups.contacts_count(resolution, %{id: group.id}, context)
      end)
    end

    # number of users in the group
    # this is an expensive operation we can come back and optimise it later
    field :users_count, :integer do
      resolve(fn group, resolution, context ->
        Resolvers.Groups.users_count(resolution, %{id: group.id}, context)
      end)
    end
  end

  @desc "Filtering options for groups"
  input_object :group_filter do
    @desc "Match the label"
    field :label, :string
  end

  input_object :group_input do
    field :label, :string
    field :description, :string
    field :is_restricted, :boolean
  end

  object :group_queries do
    @desc "get the details of one group"
    field :group, :group_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Groups.group/3)
    end

    @desc "get the stats of one group"
    field :group_info, :json do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Groups.group_info/3)
    end

    @desc "Get a list of all groups filtered by various criteria"
    field :groups, list_of(:group) do
      arg(:filter, :group_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Groups.groups/3)
    end

    @desc "Get a count of all groups filtered by various criteria"
    field :count_groups, :integer do
      arg(:filter, :group_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Groups.count_groups/3)
    end
  end

  object :group_mutations do
    field :create_group, :group_result do
      arg(:input, non_null(:group_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Groups.create_group/3)
    end

    field :update_group, :group_result do
      arg(:id, non_null(:id))
      arg(:input, :group_input)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Groups.update_group/3)
    end

    field :delete_group, :group_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Groups.delete_group/3)
    end
  end
end
