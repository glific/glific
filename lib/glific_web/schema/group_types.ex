defmodule GlificWeb.Schema.GroupTypes do
  @moduledoc """
  GraphQL Representation of Glific's Group DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers

  object :group_result do
    field :group, :group
    field :errors, list_of(:input_error)
  end

  object :group do
    field :id, :id
    field :label, :string
    field :is_restricted, :boolean
    field :type, :string
  end

  @desc "Filtering options for groups"
  input_object :group_filter do
    @desc "Match the label"
    field :label, :string
  end

  input_object :group_input do
    field :label, :string
    field :is_restricted, :boolean
    field :type, :string
  end

  object :group_queries do
    @desc "get the details of one group"
    field :group, :group_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Groups.group/3)
    end

    @desc "Get a list of all groups filtered by various criteria"
    field :groups, list_of(:group) do
      arg(:filter, :group_filter)
      arg(:opts, :opts)
      resolve(&Resolvers.Groups.groups/3)
    end

    @desc "Get a count of all groups filtered by various criteria"
    field :count_groups, :integer do
      arg(:filter, :group_filter)
      resolve(&Resolvers.Groups.count_groups/3)
    end
  end

  object :group_mutations do
    field :create_group, :group_result do
      arg(:input, non_null(:group_input))
      resolve(&Resolvers.Groups.create_group/3)
    end

    field :update_group, :group_result do
      arg(:id, non_null(:id))
      arg(:input, :group_input)
      resolve(&Resolvers.Groups.update_group/3)
    end

    field :delete_group, :group_result do
      arg(:id, non_null(:id))
      resolve(&Resolvers.Groups.delete_group/3)
    end
  end
end
