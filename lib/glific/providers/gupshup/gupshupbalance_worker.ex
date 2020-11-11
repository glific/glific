defmodule Glific.Jobs.GupshupbalanceWorker do
  @moduledoc """
  Module for checking gupshup remaining balance
  Glific.Jobs.GupshupbalanceWorker.perform_periodic(1)
  """

  import Ecto.Query

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    priority: 0

  alias Glific.{
    Jobs,
    Partners,
    Repo
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
    {:ok, response} = Tesla.get(@gupshup_balance_url, headers: [{"apikey", api_key}])
    {:ok, data} = Jason.decode(response.body)
    IO.inspect(data["balance"])

  #   case Tesla.get(@gupshup_balance_url, headers: [{"apikey", api_key}]) do
  #     {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
  #       :ok

  #     _ ->
  #       {:error, "Chatbase returned an unexpected result"}
  #   end
  # else
  #   :ok
  # end


  end
end
