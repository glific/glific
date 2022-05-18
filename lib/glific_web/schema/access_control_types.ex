defmodule GlificWeb.Schema.AccessControlTypes do
  @moduledoc """
  GraphQL Representation of Access Control DataType
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :access_control_result do
    field :access_control, :access_control
    field :errors, list_of(:input_error)
  end

  object :access_control do
    field :id, :id
    field :entity_id, :id
    field :entity_type, :entity_type_enum
    field :role_id, :id
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  @desc "Filtering options for roles"
  input_object :access_control_filter do
    @desc "Match the entity type"
    field :entity_type, :entity_type_enum
  end

  input_object :control_access_input do
    field :entity_id, :id
    field :entity_type, :entity_type_enum
    field :add_role_ids, non_null(list_of(:id))
    field :delete_role_ids, non_null(list_of(:id))
  end

  object :control_access_result do
    field :number_deleted, :integer
    field :access_controls, list_of(:access_control)
  end

  object :access_control_mutations do
    field :update_control_access, :control_access_result do
      arg(:input, :control_access_input)
      middleware(Authorize, :manager)
      resolve(&Resolvers.AccessControl.update_control_access/3)
    end
  end
end
