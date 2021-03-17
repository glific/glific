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
    gcs_params: Glific.Clients.Tap
  }

  @stir %{
    id: 13,
    name: "STiR Education"
    # blocked?: Glific.Clients.Stir
  }

  @reap_benefit %{
    id: 15
    # gcs_params: Glific.Clients.ReapBenefit
  }

  @weunlearn %{
    id: 25
    # broadcast: Glific.Clients.Weunlearn
  }

  @dev %{
    id: 1,
    name: "Glific",
    gcs_params: Glific.Clients.Tap,
    blocked?: Glific.Clients.Stir,
    broadcast: Glific.Clients.Weunlearn
  }

  @plugins %{
    @reap_benefit[:id] => @reap_benefit,
    @stir[:id] => @stir,
    @tap[:id] => @tap,
    @weunlearn[:id] => @weunlearn
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
  @spec gcs_params(map(), String.t()) :: {String.t(), String.t()}
  def gcs_params(media, bucket) do
    module_name = get_in(plugins(), [media["organization_id"], :gcs_params])

    if module_name,
      do: apply(module_name, :gcs_params, [media, bucket]),
      else: {media["remote_name"], bucket}
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
