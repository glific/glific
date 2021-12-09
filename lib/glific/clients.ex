defmodule Glific.Clients do
  @moduledoc """
  Wrapper module that allows us to invoke organization specific callback functions to
  tweak the way the system handles things. This allows clients to override functionality
  in a similar manner to plugins wordpress.

  At some point we will move this to a more extensible scheme, which is as yet undetermined
  """

  alias Glific.{Contacts.Contact, Flows.Action}

  @dev %{
    id: 1,
    name: "Glific",
    gcs_file_name: Glific.Clients.TAP,
    blocked?: Glific.Clients.Stir,
    broadcast: Glific.Clients.Weunlearn,
    webhook: Glific.Clients.DigitalGreen,
    daily_tasks: Glific.Clients.DigitalGreen
  }

  @sol %{
    id: 1,
    name: "Slam Out Loud",
    gcs_file_name: Glific.Clients.Sol
  }

  @avanti %{
    id: 10,
    name: "Avanti Fellows",
    webhook: Glific.Clients.Avanti
  }

  @tap %{
    id: 12,
    name: "The Apprentice Project",
    gcs_file_name: Glific.Clients.Tap
  }

  @stir %{
    id: 13,
    name: "STiR Education",
    webhook: Glific.Clients.Stir,
    gcs_file_name: Glific.Clients.Stir
    # blocked?: Glific.Clients.Stir
  }

  @lahilms %{
    id: 14,
    name: "Lend A Hand India",
    webhook: Glific.Clients.Lahi,
    gcs_file_name: Glific.Clients.Lahi
    # gcs_file_name: Glific.Clients.ReapBenefit
  }

  @reap_benefit %{
    id: 15,
    name: "Reap Benefit"
    # gcs_file_name: Glific.Clients.ReapBenefit
  }

  @weunlearn %{
    id: 25,
    name: "WeUnlearn"
    # broadcast: Glific.Clients.Weunlearn
  }

  @balajanaagraha %{
    id: 27,
    name: "BalaJanaagraha",
    webhook: Glific.Clients.Balajanaagraha
  }

  @digital_green %{
    id: 31,
    name: "DigitalGreen",
    webhook: Glific.Clients.DigitalGreen,
    daily_tasks: Glific.Clients.DigitalGreen
  }

  @nayi_disha %{
    id: 22,
    name: "Nayi Disha",
    webhook: Glific.Clients.NayiDisha
  }

  @plugins %{
    @sol[:id] => @sol,
    @avanti[:id] => @avanti,
    @lahilms[:id] => @lahilms,
    @reap_benefit[:id] => @reap_benefit,
    @stir[:id] => @stir,
    @tap[:id] => @tap,
    @weunlearn[:id] => @weunlearn,
    @balajanaagraha[:id] => @balajanaagraha,
    @digital_green[:id] => @digital_green,
    @nayi_disha[:id] => @nayi_disha
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
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    module_name = get_in(plugins(), [media["organization_id"], :gcs_file_name])

    if module_name,
      do: module_name.gcs_file_name(media),
      else: media["remote_name"]
  end

  @doc """
  Programmatially block clients based on organization needs. Use case could be:
  Allow only numbers from India and US
  """
  @spec blocked?(String.t(), non_neg_integer) :: boolean
  def blocked?(phone, organization_id) do
    module_name = get_in(plugins(), [organization_id, :blocked?])

    if module_name,
      do: module_name.blocked?(phone),
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
      do: module_name.broadcast(action, contact, staff_id),
      else: staff_id
  end

  @doc """
  Allow an organization to use glific functions to implement webhooks. A faster way
  of modifying the DB and doing some advanced stuff in an easy manner
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook(name, fields) do
    module_name = get_in(plugins(), [fields["organization_id"], :webhook])

    if module_name,
      do: module_name.webhook(name, fields),
      else: %{error: "Missing webhook function implementation"}
  end

  @doc """
  Allow an organization to ran a  glific functions at a daily basis.
  """
  @spec daily_tasks(non_neg_integer()) :: map()
  def daily_tasks(org_id) do
    module_name = get_in(plugins(), [org_id, :daily_tasks])

    if module_name,
      do: module_name.daily_tasks(org_id),
      else: %{error: "Missing daily function implementation"}
  end
end
