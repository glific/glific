defmodule Glific.Jobs.BSPBalanceWorker do
  @moduledoc """
  Module for checking gupshup remaining balance
  """

  alias Glific.{
    Partners,
    Providers.Gupshup.Wallet
  }

  @spec perform_periodic(non_neg_integer) :: :ok
  @doc """
  Glific.Jobs.BSPBalanceWorker. perform_periodic(1)
  periodic function for making calls to gupshup for remaining balance
  """
  def perform_periodic(organization_id) do
    organization = Partners.organization(organization_id)
    credentials = organization.services["bsp"]
    api_key = credentials.secrets["api_key"]

    case credentials.keys["url"] do
      "https://gupshup.io/" -> Wallet.balance(api_key, organization_id)
      _ -> {:error, "Invalid provider"}
    end
    :ok
  end
end
