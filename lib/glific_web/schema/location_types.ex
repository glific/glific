defmodule GlificWeb.Schema.LocationTypes do
  @moduledoc """
  GraphQL Representation of Glific's Location DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :location_result do
    field :location, :location
    field :errors, list_of(:input_error)
  end

  object :locations do
    field :id, :id
    field :longitude, :float
    field :latitude, :float
  end

  input_object :location_input do
    field :longitude, :float
    field :latitude, :float
  end

  object :location_queries do
    @desc "get the details of one location"
    field :location, :location_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Locations.location/3)
    end

    @desc "Get a list of all location"
    field :locations, list_of(:locations) do
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.Locations.locations/3)
    end
  end
end
