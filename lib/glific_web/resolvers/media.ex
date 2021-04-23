defmodule GlificWeb.Resolvers.Media do
  @moduledoc """
  Resolver to deal with file uploads, which we send directly to GCS
  """

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
    content = File.read!(media.path)
    {:ok, "Success: #{type}, #{organization_id}, #{content}"}
  end
end
