defmodule GlificWeb.Schema.ProfileTypes do
  @moduledoc """
  GraphQL Representation of Glific's Profile
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias Glific.Profiles.Profile
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :profile do
    field :id, :id
    field :name, :string
    field :profile_type, :string
    field :profile_registration_fields, :map
    field :contact_profile_fields, :map
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end
end
