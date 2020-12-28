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
  @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{"message" => message, "payload" => payload, "attrs" => attrs}}) do
    organization = Partners.organization(message["organization_id"])
    # ensure that we are under the rate limit, all rate limits are in requests/minutes
    # Refactring because of credo warning
    case ExRated.check_rate(
           organization.shortcode,
           # the bsp limit is per organization per shortcode
           1000,
           organization.services["bsp"].keys["bsp_limit"]
         ) do
      {:ok, _} ->
        with credential <- organization.services["bsp"],
             false <- is_nil(credential),
             false <- is_simulater(payload["destination"], message) do
          case process_to_gupshup(credential, payload, message, attrs) do
            # discard the message
            {:ok, _} -> :ok
            # return the error tuple
            error -> error
          end
        else
          # we are suppresssing sending this message, hence returning ok
          _ -> :ok
        end

      _ ->
        # lets sleep real briefly, so that we are not firing off many
        # jobs to the BSP after exceeding the rate limit for this second
        # so we are artifically slowing down the send rate
        Process.sleep(250)
        # we also want this job scheduled as soon as possible
        {:snooze, 1}
    end
  end

  defp is_simulater(destination, message) when destination == @simulater_phone do
    message_id = Faker.String.base64(36)

    {:ok,
     %Tesla.Env{
       __client__: %Tesla.Client{adapter: nil, fun: nil, post: [], pre: []},
       __module__: Glific.Providers.Gupshup.ApiClient,
       body: "{\"status\":\"submitted\",\"messageId\":\"simu-#{message_id}\"}",
       method: :post,
       status: 200
     }}
    |> handle_response(message)
  end

  defp is_simulater(_, _), do: false

  @spec process_to_gupshup(
          Glific.Partners.Credential.t(),
          map(),
          Glific.Messages.Message.t(),
          map()
        ) ::
          {:ok, Glific.Messages.Message.t()} | {:error, String.t()}
  defp process_to_gupshup(
         credential,
         payload,
         message,
         %{"is_hsm" => true, "params" => params, "template_uuid" => template_uuid} = _attrs
       ) do
    template_payload = %{
      "source" => payload["source"],
      "destination" => payload["destination"],
      "template" => Jason.encode!(%{"id" => template_uuid, "params" => params}),
      "src.name" => payload["src.name"]
    }

    ApiClient.post(
      credential.keys["api_end_point"] <> "/template/msg",
      template_payload,
      headers: [{"apikey", credential.secrets["api_key"]}]
    )
    |> handle_response(message)
  end

  defp process_to_gupshup(credential, payload, message, _attrs) do
    ApiClient.post(
      credential.keys["api_end_point"] <> "/msg",
      payload,
      headers: [{"apikey", credential.secrets["api_key"]}]
    )
    |> handle_response(message)
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
