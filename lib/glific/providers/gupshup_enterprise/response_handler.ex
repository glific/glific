defmodule Glific.Providers.Gupshup.Enterprise.ResponseHandler do
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

      # Not authorized, Job succeeded, we should return an ok, so we don't retry
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
  def handle_response(error, message) do
    # Adding log when API Client fails
    Logger.info(
      "Error calling API Client for org_id: #{message.organization_id} error: #{Glific.SafeLog.safe_inspect(error)}"
    )

    %{body: "{\"details\":\"Error sending message due to network issues or Gupshup Outage\"}"}
    |> add_error_payload
    |> Communications.Message.handle_error_response(message)

    :ok
  end

  @spec add_error_payload(Tesla.Env.t() | map()) :: Tesla.Env.t()
  defp add_error_payload(response) do
    # Gupshup Enterprise (or an intermediary) can return a non-JSON
    # plaintext body on infra-level failures, so decode leniently
    # instead of crashing the Oban job.
    reason =
      case Jason.decode(response.body) do
        {:ok, %{"response" => error}} -> error["details"]
        _ -> Glific.SafeLog.safe_inspect(response.body)
      end

    %{"payload" => %{"payload" => %{"reason" => reason}}}
    |> then(&Map.put(response, :body, &1))
  end

  @spec add_success_payload(Tesla.Env.t()) :: Tesla.Env.t()
  defp add_success_payload(response) do
    # Same rationale as add_error_payload/1: decode leniently instead of
    # crashing the Oban job on a non-JSON 2xx body.
    message_id =
      case Jason.decode(response.body) do
        {:ok, %{"response" => success_response}} -> success_response["id"]
        _ -> nil
      end

    %{"messageId" => message_id}
    |> then(&Map.put(response, :body, Jason.encode!(&1)))
  end

  @spec check_message_status(Tesla.Env.t()) :: String.t()
  defp check_message_status(%{body: body} = _response) do
    # A non-JSON body can't confirm success, so treat it as an error and
    # let add_error_payload/1 (which itself decodes leniently) take over.
    case Jason.decode(body) do
      {:ok, %{"response" => response}} -> response["status"]
      _ -> "error"
    end
  end
end
