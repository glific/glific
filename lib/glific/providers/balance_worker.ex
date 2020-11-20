defmodule Glific.Jobs.BSPBalanceWorker do
  @moduledoc """
  Module for checking remaining balance
  """

  alias Glific.Partners
  alias Glific.Communications

  @doc """
  periodic function for making calls to bsp for remaining balance
  Glific.Jobs.BSPBalanceWorker.perform_periodic(1)
  """
  @spec perform_periodic(non_neg_integer) :: :ok
  def perform_periodic(organization_id) do
    {:ok, data} = Partners.get_bsp_balance(organization_id)

    Communications.publish_data(
      %{key: "bsp_balance", value: %{balance: data["balance"]}},
      :periodic_info,
      organization_id
    )
    :ok
  end
end
