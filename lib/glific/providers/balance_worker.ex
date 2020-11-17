defmodule Glific.Jobs.BSPBalanceWorker do
  @moduledoc """
  Module for checking remaining balance
  """

  alias Glific.{
    Partners,
    Providers.Gupshup.GupshupWallet
  }

  @doc """
  periodic function for making calls to bsp for remaining balance
  """
  @spec perform_periodic(non_neg_integer) :: :ok
  def perform_periodic(organization_id) do
    organization = Partners.organization(organization_id)
    credentials = organization.services["bsp"]
    api_key = credentials.secrets["api_key"]

    case organization.bsp.shortcode do
      "gupshup" -> GupshupWallet.balance(api_key, organization_id)
      _ -> {:error, "Invalid provider"}
    end

    :ok
  end
end
