defmodule Glific.Providers.Gupshup.Enterprise.Worker do
  @moduledoc """
  A worker to handle send message processes
  """

  use Oban.Worker,
    queue: :gupshup,
    max_attempts: 2,
    priority: 0

  alias Glific.{
    Contacts,
    Messages.Message,
    Partners,
    Partners.Organization,
    Providers.Gupshup.Enterprise.ApiClient,
    Providers.ResponseHandler
  }

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{"message" => message}} = job) do
    organization = Partners.organization(message["organization_id"])

    if is_nil(organization.services["bsp"]) do
      ResponseHandler.handle_fake_response(
        message,
        "{\"message\": \"BSP credentials does not exist\"}",
        401
      )
    else
      perform(job, organization)
    end
  end

  @spec perform(Oban.Job.t(), Organization.t()) ::
          :ok | {:error, String.t()} | {:snooze, pos_integer()}
  defp perform(
         %Oban.Job{args: %{"message" => message, "payload" => payload, "attrs" => attrs}},
         organization
       ) do
    # ensure that we are under the rate limit, all rate limits are in requests/minutes
    # Refactoring because of credo warning
    case ExRated.check_rate(
           organization.shortcode,
           # the bsp limit is per organization per shortcode
           1000,
           organization.services["bsp"].keys["bsp_limit"]
         ) do
      {:ok, _} ->
        if Contacts.is_simulator_contact?(payload["send_to"]) do
          process_simulator(payload["send_to"], message)
        else
          process_gupshup(organization.id, payload, message, attrs)
        end

      _ ->
        # lets sleep real briefly, so that we are not firing off many
        # jobs to the BSP after exceeding the rate limit for this second
        # so we are artifically slowing down the send rate
        Process.sleep(50)
        # we also want this job scheduled as soon as possible
        {:snooze, 1}
    end
  end

  @spec process_simulator(String.t(), Message.t()) :: :ok | {:error, String.t()}
  defp process_simulator(_destination, message) do
    message_id = Faker.String.base64(36)

    ResponseHandler.handle_fake_response(
      message,
      "{\"status\":\"submitted\",\"messageId\":\"simu-#{message_id}\"}",
      200
    )
  end

  defp process_gupshup(org_id, payload, message, _attrs) do
    ApiClient.send_message(
      org_id,
      payload
    )
    |> ResponseHandler.handle_response(message)
  end
end
