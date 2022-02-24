defmodule Glific.Providers.Gupshup.Enterprise.ResponseHandler do
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
        if check_message_status(response) == "error" do
          response
          |> add_error_payload
          |> Communications.Message.handle_error_response(message)
        else
          response
          |> add_success_payload
          |> Communications.Message.handle_success_response(message)
        end

        :ok

      # Not authorized, Job succeeded, we should return an ok, so we dont retry
      %Tesla.Env{status: status} when status in 400..499 ->
        response
        |> add_error_payload
        |> Communications.Message.handle_error_response(message)

        :ok

      _ ->
        response
        |> add_error_payload
        |> Communications.Message.handle_error_response(message)
    end
  end

  # Sending default error when API Client call fails for some reason
  def handle_response(_error, message) do
    %{body: "{\"details\":\"Error sending message due to network issues or Gupshup Outage\"}"}
    |> add_error_payload
    |> Communications.Message.handle_error_response(message)

    :ok
  end

  @spec add_error_payload(Tesla.Env.t() | map()) :: Tesla.Env.t()
  defp add_error_payload(response) do
    %{"response" => error} = Jason.decode!(response.body)

    %{"payload" => %{"payload" => %{"reason" => error["details"]}}}
    |> then(&Map.put(response, :body, &1))
  end

  @spec add_success_payload(Tesla.Env.t()) :: Tesla.Env.t()
  defp add_success_payload(response) do
    %{"response" => success_response} = Jason.decode!(response.body)

    %{"messageId" => success_response["id"]}
    |> then(&Map.put(response, :body, Jason.encode!(&1)))
  end

  @spec check_message_status(Tesla.Env.t()) :: String.t()
  defp check_message_status(%{body: body} = _response) do
    %{"response" => response} = Jason.decode!(body)
    response["status"]
  end
end
