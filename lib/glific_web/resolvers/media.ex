defmodule GlificWeb.Resolvers.Media do
  @moduledoc """
  Resolver to deal with file uploads, which we send directly to GCS
  """
  alias Glific.GCS.GcsWorker

  @doc """
  Upload a file given its type (to determine the extention)
  """
  @spec upload(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def upload(
        _,
        %{media: media, type: type, organization_id: organization_id},
        _context
      ) do
    remote_name = "media/" <> Ecto.UUID.generate() <> "." <> type
    GcsWorker.upload_media(media.path, remote_name, organization_id)
  end
end
