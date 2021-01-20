defmodule Glific.Providers.Gupshup.Worker do
  @moduledoc """
  A worker to handle send message processes
  """

  use Oban.Worker,
    queue: :gupshup,
    max_attempts: 2,
    priority: 0

  alias Glific.{
    Communications,
    Messages.Message,
    Partners,
    Partners.Organization,
    Providers.Gupshup.ApiClient
  }

  @simulater_phone "9876543210"

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, String.t()} | {:snooze, pos_integer()}
  def perform(%Oban.Job{args: %{"message" => message}} = job) do
    organization = Partners.organization(message["organization_id"])

    if is_nil(organization.services["bsp"]) do
      handle_fake_response(
        message,
        "{\"message\": \"API Key does not exist\"}",
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
        if payload["destination"] == @simulater_phone do
          process_simulator(payload["destination"], message)
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

    handle_fake_response(
      message,
      "{\"status\":\"submitted\",\"messageId\":\"simu-#{message_id}\"}",
      200
    )
  end

  @spec handle_fake_response(Message.t(), String.t(), non_neg_integer) ::
          :ok | {:error, String.t()}
  defp handle_fake_response(message, body, status) do
    {:ok,
     %Tesla.Env{
       __client__: %Tesla.Client{adapter: nil, fun: nil, post: [], pre: []},
       __module__: Glific.Providers.Gupshup.ApiClient,
       body: body,
       method: :post,
       status: status
     }}
    |> handle_response(message)
  end

  @spec process_gupshup(
          non_neg_integer(),
          map(),
          Message.t(),
          map()
        ) ::
          {:ok, Message.t()} | {:error, String.t()}
  defp process_gupshup(
         org_id,
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

    ApiClient.send_template(
      org_id,
      template_payload
    )
    |> handle_response(message)
  end

  defp process_gupshup(org_id, payload, message, _attrs) do
    ApiClient.send_message(
      org_id,
      payload
    )
    |> handle_response(message)
  end

  @doc false
  @spec handle_response({:ok, Tesla.Env.t()}, Message.t()) ::
          :ok | {:error, String.t()}
  defp handle_response({:ok, response}, message) do
    case response do
      %Tesla.Env{status: 200} ->
        Communications.Message.handle_success_response(response, message)
        :ok

      # Not authorized, Job succeeded, we should return an ok, so we dont retry
      %Tesla.Env{status: 401} ->
        Communications.Message.handle_error_response(response, message)
        :ok

      # We dont know why this failed, so we should try again
      _ ->
        Communications.Message.handle_error_response(response, message)
    end
  end
end
