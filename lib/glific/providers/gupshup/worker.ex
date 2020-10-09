defmodule Glific.Providers.Gupshup.Worker do
  @moduledoc """
  A worker to handle send message processes
  """

  use Oban.Worker,
    queue: :gupshup,
    max_attempts: 1,
    priority: 0

  alias Glific.{
    Communications,
    Partners,
    Providers.Gupshup.ApiClient
  }

  @simulater_phone "9876543210"
  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"message" => message, "payload" => payload}}) do
    organization = Partners.organization(message["organization_id"])
    # ensure that we are under the rate limit, all rate limits are in requests/minutes
    # Refactring because of credo warning
    case ExRated.check_rate(
           organization.shortcode,
           60_000,
           organization.services["bsp"].keys["bsp_limit"]
         ) do
      {:ok, _} ->
        with credential <- organization.services["bsp"],
             false <- is_nil(credential),
             do: check_simulator(credential, payload, message)
      _ ->
        {:error, :rate_limit_exceeded}
    end

    :ok
  end

  defp check_simulator(credential, payload, message) do
    receiver = Glific.Contacts.get_contact!(message["receiver_id"])
    if receiver.phone == @simulater_phone do
      messageID = Faker.String.base64(36)
    {:ok,
    %Tesla.Env{
      __client__: %Tesla.Client{adapter: nil, fun: nil, post: [], pre: []},
      __module__: Glific.Providers.Gupshup.ApiClient,
      body: "{\"status\":\"submitted\",\"messageId\":\"#{messageID}\"}",
      method: :post,
      status: 200,
    }}
    |> handle_response(message)
    else
      ApiClient.post(
        credential.keys["api_end_point"] <> "/msg",
        payload,
        headers: [{"apikey", credential.secrets["api_key"]}]
      )
      |> handle_response(message)
    end
  end

  @doc false
  @spec handle_response({:ok, Tesla.Env.t()}, Glific.Messages.Message.t()) ::
          {:ok, Glific.Messages.Message.t()} | {:error, String.t()}
  defp handle_response({:ok, response}, message) do
    case response do
      %Tesla.Env{status: 200} -> Communications.Message.handle_success_response(response, message)
      _ -> Communications.Message.handle_error_response(response, message)
    end
  end
end
