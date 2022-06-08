defmodule GlificWeb.Schema.ProfileTypes do
  @moduledoc """
  GraphQL Representation of Glific's Profile
  """

  use Absinthe.Schema.Notation
  # import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  # alias Glific.Repo
  # alias Glific.Profiles.Profile
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :profile_result do
    field :profile, :profile
    field :errors, list_of(:input_error)
  end

  object :profile do
    field :id, :id
    field :name, :string
    field :profile_type, :string
    field :profile_registration_fields, :json
    field :contact_profile_fields, :json
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  input_object :profile_input do
    field :name, :string
    field :profile_type, :string
    field :profile_registration_fields, :json
    field :language_id, :id
    field :contact_id, :id
    field :organization_id, :id
    field :contact_profile_fields, :json
  end

  object :profile_mutations do
    field :create_profile, :profile_result do
      arg(:input, non_null(:profile_input))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Profiles.create_profile/3)
    end

    field :update_profile, :profile_result do
      arg(:id, non_null(:id))
      arg(:input, :profile_input)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Profiles.update_profile/3)
    end

    field :delete_profile, :profile_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :manager)
      resolve(&Resolvers.Profiles.delete_profile/3)
    end
  end
end
