defmodule Glific.Jobs.GupshupbalanceWorker do
  @moduledoc """
  Module for checking gupshup remaining balance
  Glific.Jobs.GupshupbalanceWorker.perform_periodic(1)
  """

  alias Glific.{
    Communications,
    Partners,
  }

  @spec perform_periodic(non_neg_integer) :: :ok
  @doc """
  periodic function for making calls to gupshup for remaining balance
  """
  @gupshup_balance_url "https://api.gupshup.io/sm/api/v2/wallet/balance"
  def perform_periodic(organization_id) do
    organization = Partners.organization(organization_id)
    credentials = organization.services["gupshup"]
    api_key = credentials.secrets["api_key"]
    case Tesla.get(@gupshup_balance_url, headers: [{"apikey", api_key}]) do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, data} = Jason.decode(body)
        IO.inspect(data["balance"])
        _ ->
        {:error, "Invalid key"}
    end

  end
end
