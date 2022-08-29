defmodule GlificWeb.Schema.ProfileTypes do
  @moduledoc """
  GraphQL Representation of Glific's Profile
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers
  import Ecto.Query, warn: false

  alias Glific.Repo

  alias GlificWeb.{
    Resolvers,
    Schema.Middleware.Authorize
  }

  object :profile_result do
    field :profile, :profile
    field :errors, list_of(:input_error)
  end

  object :profile do
    field :id, :id
    field :name, :string
    field :type, :string
    field :fields, :json
    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :language, :language do
      resolve(dataloader(Repo, use_parent: true))
    end
  end

  input_object :profile_input do
    field :name, :string
    field :type, :string
    field :fields, :json
    field :language_id, :id
    field :contact_id, :id
    field :organization_id, :id
  end

  input_object :profile_filter do
    @desc "Search by organization id"
    field(:organization_id, :id)

    @desc "Search by contact id"
    field(:contact_id, :id)

    @desc "search profile by name"
    field(:name, :string)
  end

  object :profile_queries do
    @desc "get the details of one profile"
    field :profile, :profile_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Profiles.profile/3)
    end

    @desc "Get a list of all profiles filtered by various criteria"
    field :profiles, list_of(:profile) do
      arg(:filter, :profile_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Profiles.profiles/3)
    end
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
