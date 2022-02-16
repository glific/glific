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
  @spec handle_response({:ok, Tesla.Env.t()}, Message.t()) ::
          :ok | {:error, String.t()}
  def handle_response({:ok, response}, message) do
    case response do
      %Tesla.Env{status: status} when status in 200..299 ->
        if check_message_status(response) == "error" do
          response
          |> add_error_payload
          |> Communications.Message.handle_error_response(message)
        else
          Communications.Message.handle_success_response(response, message)
        end

        :ok

      # Not authorized, Job succeeded, we should return an ok, so we dont retry
      %Tesla.Env{status: status} when status in 400..499 ->
        Communications.Message.handle_error_response(response, message)
        :ok

      _ ->
        Communications.Message.handle_error_response(response, message)
    end
  end

  defp add_error_payload(response) do
    %{"response" => error} = Jason.decode!(response.body)

    %{"payload" => %{"payload" => %{"reason" => error["details"]}}}
    |> then(&Map.put(response, :body, &1))
  end

  defp check_message_status(%{body: body} = _response) do
    %{"response" => response} = Jason.decode!(body)
    response["status"]
  end
end
