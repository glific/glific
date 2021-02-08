defmodule Glific.Jobs.BSPBalanceWorker do
  @moduledoc """
  Module for checking remaining balance
  """

  alias Glific.{
    Communications,
    Partners
  }

  require Logger

  @doc """
  periodic function for making calls to bsp for remaining balance
  """
  @spec perform_periodic(non_neg_integer) :: :ok
  def perform_periodic(organization_id) do
    Logger.info("Checking BSP balance: organization_id: '#{organization_id}'")

    Partners.get_bsp_balance(organization_id)
    |> case do
      {:ok, data} ->
        # We should move this to an embedded schema
        # and then fix the function in publish_data. Basically have a periodic
        # status message packet sent to frontend with this and other details
        Communications.publish_data(
          %{"balance" => data["balance"]},
          :periodic_info,
          organization_id
        )

      _ ->
        nil
    end

    :ok
  end
end
