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

    @desc "upload a media blob encoded in base 64 and type"
    field :upload_blob, :string do
      arg(:media, non_null(:string))
      arg(:type, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Media.upload_blob/3)
    end
  end
end
