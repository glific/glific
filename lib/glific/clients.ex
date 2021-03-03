defmodule Glific.Clients do
  @moduledoc """
  Wrapper module that allows us to invoke organization specific callback functions to
  tweak the way the system handles things. This allows clients to override functionality
  in a similar manner to plugins wordpress.

  At some point we will move this to a more extensible scheme, which is as yet undetermined
  """

  @plugins %{
    1 => %{
      name: "The Apprentice Project",
      gcs_bucket: Glific.Clients.Tap
    },
    2 => %{
      name: "STiR Education",
      webhook: Glific.Clients.Stir
    }
  }

  @doc """
  Overwrite the default GCS storage bucket
  """
  @spec gcs_bucket(map(), String.t()) :: String.t()
  def gcs_bucket(media, default) do
    module_name = get_in(@plugins, [media["organization_id"], :gcs_bucket])

    if module_name do
      apply(@plugins[media["organization_id"][:gcs_bucket]], :gcs_bucket, [media])
    else
      default
    end
  end
end
