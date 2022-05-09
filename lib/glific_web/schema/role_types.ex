defmodule GlificWeb.Schema.RoleTypes do
  @moduledoc """
  GraphQL Representation of Role DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :access_role_result do
    field :access_role, :access_role
    field :errors, list_of(:input_error)
  end

  object :access_role do
    field :id, :id
    field :label, :string
    field :description, :string
    field :is_reserved, :boolean
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  @desc "Filtering options for roles"
  input_object :access_role_filter do
    @desc "Match the label"
    field :label, :string

    @desc "Match the shortcode"
    field :description, :string

    @desc "Match the reserved flag"
    field :is_reserved, :boolean
  end

  input_object :access_role_input do
    field :label, :string
    field :description, :string
    field :is_reserved, :boolean
  end

  object :access_role_queries do
    @desc "get the details of one role"
    field :access_role, :access_role_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Roles.role/3)
    end

    @desc "Get a list of all roles filtered by various criteria"
    field :access_roles, list_of(:access_role) do
      arg(:filter, :access_role_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Roles.roles/3)
    end
  end

  object :access_role_mutations do
    field :create_role, :access_role_result do
      arg(:input, non_null(:access_role_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Roles.create_role/3)
    end

    field :update_role, :access_role_result do
      arg(:id, non_null(:id))
      arg(:input, :access_role_input)
      middleware(Authorize, :manager)
      resolve(&Resolvers.Roles.update_role/3)
    end

    field :delete_role, :access_role_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Roles.delete_role/3)
    end
  end
end
