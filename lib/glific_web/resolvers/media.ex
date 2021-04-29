defmodule GlificWeb.Resolvers.Media do
  @moduledoc """
  Resolver to deal with file uploads, which we send directly to GCS
  """
  alias Glific.{GCS.GcsWorker, Users.User}

  @doc """
  Upload a file given its type (to determine the extention)
  """
  @spec upload(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def upload(
        _,
        %{media: media, type: type, organization_id: organization_id},
        %{context: %{current_user: user}}
      ) do
    GcsWorker.upload_media(media.path, remote_name(user, type), organization_id)
  end

  @doc """
  Upload a blob encoded in base64 given its type (to determine the extention)
  """
  @spec upload_blob(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def upload_blob(
        _,
        %{media: media, type: type, organization_id: organization_id},
        %{context: %{current_user: user}}
      ) do
    uuid = Ecto.UUID.generate()

    # first decode blob and store in temp file
    local_file =
      File.write!(
        local_name(type, uuid),
        Base.decode64!(media)
      )

    GcsWorker.upload_media(local_file, remote_name(user, type, uuid), organization_id)
  end

  @spec local_name(String.t(), Ecto.UUID.t()) :: String.t()
  defp local_name(type, uuid),
    do: "#{System.tmp_dir!()}/#{uuid}.#{type}"

  @spec remote_name(User.t(), String.t(), Ecto.UUID.t() | nil) :: String.t()
  defp remote_name(user, type, uuid \\ Ecto.UUID.generate()) do
    {year, week} = Timex.iso_week(Timex.now())
    "outbound/#{year}-#{week}/#{user.name}/#{uuid}.#{type}"
  end
end
