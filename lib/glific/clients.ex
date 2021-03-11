defmodule Glific.Clients do
  @moduledoc """
  Wrapper module that allows us to invoke organization specific callback functions to
  tweak the way the system handles things. This allows clients to override functionality
  in a similar manner to plugins wordpress.

  At some point we will move this to a more extensible scheme, which is as yet undetermined
  """

  alias Glific.{Contacts.Contact, Flows.Action}

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

  @weunlearn %{
    id: 25,
    broadcast: Glific.Clients.Weunlearn
  }

  @dev %{
    id: 1,
    name: "Glific",
    gcs_bucket: Glific.Clients.Tap,
    broadcast: Glific.Clients.Weunlearn
  }

  @test %{
    id: 1,
    name: "Glific",
    gcs_bucket: Glific.Clients.Tap,
    blocked?: Glific.Clients.Stir,
    broadcast: Glific.Clients.Weunlearn
  }

  @plugins %{
    @tap[:id] => @tap,
    @stir[:id] => @stir,
    @weunlearn[:id] => @weunlearn
  }

  @spec env(atom() | nil) :: atom()
  defp env(nil), do: Application.get_env(:glific, :environment)
  defp env(e), do: e

  @doc false
  @spec plugins(atom() | nil) :: map()
  def plugins(e \\ nil) do
    env(e)
    |> case do
      :prod -> @plugins
      # for testing and development we'll use org id 1
      :test -> @test
      _ -> @dev
    end
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

  @doc """
  Allow an organization to dynamically select which contact the broadcast message should
  go to. This gives NGOs more flexibility when building flows
  """
  @spec broadcast(Action.t(), Contact.t(), non_neg_integer) :: non_neg_integer
  def broadcast(action, contact, staff_id) do
    module_name = get_in(plugins(), [contact.organization_id, :broadcast])

    if module_name,
      do: apply(module_name, :broadcast, [action, contact, staff_id]),
      else: staff_id
  end
end
