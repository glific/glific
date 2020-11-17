defmodule Glific.Providers.Gupshup.Wallet do
  @moduledoc """
  Module for checking gupshup remaining balance
  """
  alias Glific.Communications

  @gupshup_balance_url "https://api.gupshup.io/sm/api/v2/wallet/balance"

  @doc """
  function for making call to gupshup for remaining balance
  """
  @spec balance(String.t(), non_neg_integer) :: {:ok}
  def balance(api_key, organization_id) do
    case Tesla.get(@gupshup_balance_url, headers: [{"apikey", api_key}]) do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, data} = Jason.decode(body)
        Communications.publish_data(%{key: "bsp_balance", value: %{balance: data["balance"]}}, :periodic_info, organization_id)
      _ ->
        {:error, "Invalid key"}
    end
    {:ok}
  end
end
