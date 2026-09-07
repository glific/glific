defmodule GlificWeb.Schema.MediaTypes do
  @moduledoc """
  GraphQL Representation of Glific's Location DataType
  """
  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  @desc "Whose Google Cloud Storage an upload is written to"
  enum :upload_storage_enum do
    value(:organization, description: "the uploading organisation's own bucket")
    value(:saas, description: "the platform's bucket, for orgs that have no GCS of their own")
  end

  object :media_mutations do
    @desc "upload a media file and type"
    field :upload_media, :string do
      arg(:media, non_null(:upload))
      arg(:extension, non_null(:string))

      @desc "reject anything larger, in kilobytes. Omitted means no limit."
      arg(:max_size_kb, :integer)

      @desc "file under <folder>/<org id>/<uuid>.<ext>. Omitted uses the attachment path."
      arg(:folder, :string)

      @desc "which Google Cloud Storage account to write to. Defaults to the organisation's."
      arg(:storage, :upload_storage_enum, default_value: :organization)

      middleware(Authorize, :staff)
      resolve(&Resolvers.Media.upload/3)
    end

    @desc "upload a media blob encoded in base 64 and type"
    field :upload_blob, :string do
      arg(:media, non_null(:string))
      arg(:extension, non_null(:string))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Media.upload_blob/3)
    end
  end
end
