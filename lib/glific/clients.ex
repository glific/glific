defmodule Glific.Clients do
  @moduledoc """
  Wrapper module that allows us to invoke organization specific callback functions to
  tweak the way the system handles things. This allows clients to override functionality
  in a similar manner to plugins wordpress.

  At some point we will move this to a more extensible scheme, which is as yet undetermined
  """

  @tap %{
    id: 12,
    name: "The Apprentice Project",
    gcs_bucket: Glific.Clients.Tap
  }

  @stir %{
    id: 13,
    name: "STiR Education",
    webhook: Glific.Clients.Stir,
    blocked?: Glific.Clients.Stir
  }

  @dev %{
    id: 1,
    name: "Glific"
    gcs_bucket: Glific.Clients.Tap
  }

  @plugins %{
    @tap[:id] => @tap,
    @stir[:id] => @stir
  }

  @spec env(atom() | nil) :: atom()
  defp env(nil), do: Application.get_env(:glific, :environment)
  defp env(e), do: e

  @doc false
  @spec plugins(atom() | nil) :: map()
  def plugins(e \\ nil) do
    if env(e) == :prod,
      do: @plugins,
      # for testing and development we'll use org id 1
      else: %{@dev[:id] => @dev}
  end

  @doc """
  Overwrite the default GCS storage bucket
  """
  @spec gcs_bucket(map(), String.t()) :: String.t()
  def gcs_bucket(media, default) do
    module_name = get_in(plugins(), [media["organization_id"], :gcs_bucket])

    if module_name,
      do: apply(module_name, :gcs_bucket, [media, default]),
      else: default
  end

  @doc """
  Programmatially block clients based on organization needs. Use case could be:
  Allow only numbers from India and US
  """
  @spec blocked?(String.t(), non_neg_integer) :: boolean
  def blocked?(phone, organization_id) do
    module_name = get_in(plugins(), [organization_id, :blocked?])

    if module_name,
      do: apply(module_name, :blocked?, [phone]),
      else: false
  end
end
