defmodule Glific.Providers.Worker do
  @moduledoc """
  A common worker to handle send message processes irrespective of BSP
  """
  alias Glific.{
    Communications,
    Messages.Message
  }

  @spec handle_credential_error(Message.t()) :: :ok | {:error, String.t()}
  def handle_credential_error(message) do
    handle_fake_response(
      message,
      "{\"message\": \"BSP credentials does not exist\"}",
      401
    )
  end

  @spec process_simulator(Message.t()) :: :ok | {:error, String.t()}
  def process_simulator(message) do
    message_id = Faker.String.base64(36)

    handle_fake_response(
      message,
      "{\"status\":\"submitted\",\"messageId\":\"simu-#{message_id}\"}",
      200
    )
  end

  @doc false
  @spec handle_fake_response(Message.t(), String.t(), non_neg_integer) ::
          :ok | {:error, String.t()}
  def handle_fake_response(message, body, status) do
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

  @doc false
  @spec handle_response({:ok, Tesla.Env.t()}, Message.t()) ::
          :ok | {:error, String.t()}
  def handle_response({:ok, response}, message) do
    case response do
      %Tesla.Env{status: status} when status in 200..299 ->
        Communications.Message.handle_success_response(response, message)
        :ok

      # Not authorized, Job succeeded, we should return an ok, so we dont retry
      %Tesla.Env{status: status} when status in 400..499 ->
        Communications.Message.handle_error_response(response, message)
        :ok

      _ ->
        Communications.Message.handle_error_response(response, message)
    end
  end

  @spec default_send_rate_handler() :: {:snooze, pos_integer()}
  def default_send_rate_handler do
    # lets sleep real briefly, so that we are not firing off many
    # jobs to the BSP after exceeding the rate limit for this second
    # so we are artifically slowing down the send rate
    Process.sleep(50)
    # we also want this job scheduled as soon as possible
    {:snooze, 1}
  end
end
