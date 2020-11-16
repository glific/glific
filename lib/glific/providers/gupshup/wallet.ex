defmodule Glific.Providers.Gupshup.Wallet do
  @moduledoc """
  Module for checking gupshup remaining balance
  """
  alias Glific.{
    Communications,
    Partners,
  }

  @doc """
  function for making calls to gupshup for remaining balance
  """
  @gupshup_balance_url "https://api.gupshup.io/sm/api/v2/wallet/balance"

  def balance(api_key) do
    case Tesla.get(@gupshup_balance_url, headers: [{"apikey", api_key}]) do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, data} = Jason.decode(body)
         IO.inspect(data["balance"])
         _ ->{:error, "Invalid key"}
    end

  end
end
