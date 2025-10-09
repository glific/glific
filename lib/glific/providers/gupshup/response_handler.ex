defmodule Glific.Providers.Gupshup.ResponseHandler do
  @moduledoc """
  Module for handling response from Provider end
  or Handle response for simulators
  """
  alias Glific.{
    Communications,
    Messages.Message
  }

  require Logger

  @doc false
  @spec handle_response({:ok, Tesla.Env.t()}, Message.t() | {:error, any()}) ::
          :ok | {:error, String.t()}
  def handle_response({:ok, response}, message) do
    case response do
      %Tesla.Env{status: status} when status in 200..299 ->
        Communications.Message.handle_success_response(response, message)
        :ok

      # Not authorized, Job succeeded, we should return an ok, so we don't retry
      %Tesla.Env{status: status} when status in 400..499 ->
        Communications.Message.handle_error_response(response, message)
        :ok

      _ ->
        Communications.Message.handle_error_response(response, message)
    end
  end

  @default_tesla_error %{
    "payload" => %{
      "payload" => %{
        "reason" => "Error sending message due to network issues or Gupshup Outage"
      }
    }
  }

  def handle_response(error, message) do
    # Adding log when API Client fails
    Logger.error(
      "Error calling API Client for org_id: #{message["organization_id"]} error: #{inspect(error)}"
    )

    # Sending default error when API Client call fails for some reason
    err =
      Communications.Message.handle_error_response(
        %{body: put_in(@default_tesla_error, ["payload", "payload", "error"], inspect(error))},
        message
      )

    case error do
      {:error, reason} when reason in [:timeout, :closed_timeout, :closed] ->
        # This will kickoff oban retry mechanism for timeout related errors
        err

      _ ->
        :ok
    end
  end
end
