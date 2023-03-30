defmodule Glific.Providers.Airtel.Wallet do
  @moduledoc """
  Module for checking airtel remaining balance
  """
  import GlificWeb.Gettext

  @airtel_balance_url "https://api.airtel.io/sm/api/v2/wallet/balance"

  @doc """
  function for making call to airtel for remaining balance
  """
  @spec balance(String.t()) :: {:ok, any()} | {:error, String.t()}
  def balance(api_key) do
    case Tesla.get(@airtel_balance_url, headers: [{"apikey", api_key}]) do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        Jason.decode(body)

      {:ok, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        {:error, body}

      _ ->
        {:error, dgettext("errors", "Invalid BSP API key")}
    end
  end
end
