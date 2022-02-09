defmodule Glific.Providers.Worker do
  @moduledoc """
  A common worker to handle send message processes irrespective of BSP
  """
  alias Glific.{
    Messages.Message,
    Providers.ResponseHandler
  }

  @spec handle_credential_error(Message.t()) :: :ok | {:error, String.t()}
  def handle_credential_error(message) do
    ResponseHandler.handle_fake_response(
      message,
      "{\"message\": \"BSP credentials does not exist\"}",
      401
    )
  end

  @spec process_simulator(Message.t()) :: :ok | {:error, String.t()}
  def process_simulator(message) do
    message_id = Faker.String.base64(36)

    ResponseHandler.handle_fake_response(
      message,
      "{\"status\":\"submitted\",\"messageId\":\"simu-#{message_id}\"}",
      200
    )
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
