defmodule Glific.Providers.Gupshup.GupshupWallet do
  @moduledoc """
  Module for checking gupshup remaining balance
  """
  use Gettext, backend: GlificWeb.Gettext

  @gupshup_balance_url "https://api.gupshup.io/sm/api/v2/wallet/balance"

  @doc """
  function for making call to gupshup for remaining balance
  """
  @spec balance(String.t()) :: {:ok, any()} | {:error, String.t()}
  def balance(api_key) do
    case Tesla.get(@gupshup_balance_url, headers: [{"apikey", api_key}]) do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        Jason.decode(body)

      {:ok, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        {:error, body}

      _ ->
        {:error, dgettext("errors", "Invalid BSP API key")}
    end
  end
end
