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
        Communications.publish_data(
          %{key: "bsp_balance", value: %{balance: data["balance"]}},
          :periodic_info,
          organization_id
        )

      _ ->
        nil
    end

    :ok
  end
end
