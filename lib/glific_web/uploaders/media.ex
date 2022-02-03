defmodule Glific.Media do
  @moduledoc """
  This is an auto generated file from waffle, that is used to control storage behavior
  """
  use Waffle.Definition

  # Include ecto support (requires package waffle_ecto installed):
  use Waffle.Ecto.Definition

  @versions [:original]

  alias Glific.Partners

  # To add a thumbnail version:
  # @versions [:original, :thumb]

  # Override the bucket on a per definition basis:
  def bucket({_file, org_id}) when is_binary(org_id) do
    organization =
      String.to_integer(org_id)
      |> Partners.organization()

    organization.services["google_cloud_storage"]
    |> case do
      nil -> "custom_bucket_name"
      credentials -> credentials.secrets["bucket"]
    end
  end

  def bucket(_attr),
    do: Glific.GCS.get_bucket_name()

  # Whitelist file extensions:
  def validate({file, _}) do
    ~w(.jpg .jpeg .gif .png .pdf .wav .mp3 .mp4 .aac .mpeg)
    |> Enum.member?(Path.extname(file.file_name))
  end

  # Define a thumbnail transformation:
  # def transform(:thumb, _) do
  #   {:convert, "-strip -thumbnail 250x250^ -gravity center -extent 250x250 -format png", :png}
  # end

  # we want to retain our filename which potentially has
  # directory structure in it, and hence over-riding the default from
  # waffle. So using rootname instead of basename
  def filename(_, {file, _}) do
    Path.rootname(file.file_name, Path.extname(file.file_name))
  end

  # Override the storage directory:
  # def storage_dir(version, {file, scope}) do
  #   "uploads/user/avatars/#{scope.id}"
  # end

  # Provide a default URL if there hasn't been a file uploaded
  # def default_url(version, scope) do
  #   "/images/avatars/default_#{version}.png"
  # end

  # Specify custom headers for s3 objects
  # Available options are [:cache_control, :content_disposition,
  #    :content_encoding, :content_length, :content_type,
  #    :expect, :expires, :storage_class, :website_redirect_location]
  #
  # def s3_object_headers(version, {file, scope}) do
  #   [content_type: MIME.from_path(file.file_name)]
  # end

  def gcs_object_headers(_version, {file, _scope}) do
    %{contentType: MIME.from_path(file.file_name)}
  end
end
