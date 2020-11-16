defmodule Glific.Providers.Gupshup.Wallet do
  @moduledoc """
  Module for checking gupshup remaining balance
  """
  alias Glific.{
    Communications,
    Partners,
  }

  @spec balance(String.t()) :: integer
  @doc """
  function for making calls to gupshup for remaining balance
  """
  @gupshup_balance_url "https://api.gupshup.io/sm/api/v2/wallet/balance"

  def balance(api_key, organization_id) do
    case Tesla.get(@gupshup_balance_url, headers: [{"apikey", api_key}]) do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, data} = Jason.decode(body)
         Communications.publish_data(data["balance"], :glific, organization_id)
         _ ->{:error, "Invalid key"}
    end

  end
end
