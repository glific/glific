defmodule Glific.Providers.Gupshup.ResponseHandler do
  @moduledoc """
  Module for handling response from Provider end
  or Handle response for simulators
  """
  alias Glific.{
    Communications,
    Messages.Message
  }

  @doc false
  @spec handle_response({:ok, Tesla.Env.t()}, Message.t() | {:error, any()}) ::
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

  @default_tesla_error %{
    "payload" => %{
      "payload" => %{
        "reason" => "Error sending message due to network issues or Gupshup Outage"
      }
    }
  }
  # Sending default error when API Client call fails for some reason
  def handle_response(_error, message) do
    Communications.Message.handle_error_response(%{body: @default_tesla_error}, message)
    :ok
  end
end
