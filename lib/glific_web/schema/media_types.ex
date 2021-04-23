defmodule GlificWeb.Schema.MediaTypes do
  @moduledoc """
  GraphQL Representation of Glific's Location DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :media_mutations do
    @desc "upload a media file and type"
    field :upload_media, :string do
      arg(:media, non_null(:upload))
      arg(:type, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Media.upload/3)
    end
  end
end
