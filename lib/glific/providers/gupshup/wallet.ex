defmodule Glific.Providers.Gupshup.GupshupWallet do
  @moduledoc """
  Module for checking gupshup remaining balance
  """
  @gupshup_balance_url "https://api.gupshup.io/sm/api/v2/wallet/balance"

  @doc """
  function for making call to gupshup for remaining balance
  """
  def balance(api_key) do
    case Tesla.get(@gupshup_balance_url, headers: [{"apikey", api_key}]) do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        Jason.decode(body)
      _ ->
        {:error, "Invalid key"}
    end
  end
end
