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
    |> IO.inspect(label: "GCS")
  end

  @spec remote_name(User.t(), String.t()) :: String.t()
  defp remote_name(user, type) do
    {year, week} = Timex.iso_week(Timex.now())
    uuid = Ecto.UUID.generate()
    "outbound/#{year}-#{week}/#{user.name}/#{uuid}.#{type}"
  end
end
