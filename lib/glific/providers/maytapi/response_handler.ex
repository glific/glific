defmodule Glific.Providers.Maytapi.ResponseHandler do
  @moduledoc """
  Module for handling response from Provider end
  or Handle response for simulators
  """

  alias Glific.{
    Communications,
    Notifications,
    Repo,
    WAGroup.WAMessage,
    WAMessages
  }

  require Logger

  @default_tesla_error """
  {\"success\":false,\"message\":\"Error sending message due to network issues or maytapi Outage\"}
  """

  @doc false
  @spec handle_response({:ok, Tesla.Env.t()}, WAMessage.t() | {:error, any()}) ::
          :ok | {:error, String.t()}
  def handle_response({:ok, response}, message) do
    case response do
      %Tesla.Env{status: status} when status in 200..299 ->
        handle_success_response(response, message)

      # Not authorized, Job succeeded, we should return an ok, so we don't retry
      %Tesla.Env{status: status} when status in 400..499 ->
        handle_error_response(response, message)

      _ ->
        handle_error_response(response, message)
    end
  end

  # Sending default error when API Client call fails for some reason
  def handle_response(error, message) do
    # Adding log when API Client fails
    Logger.info(
      "Error calling API Client for org_id: #{message.organization_id} error: #{inspect(error)}"
    )

    handle_error_response(%{body: @default_tesla_error}, message)
  end

  @spec handle_success_response(Tesla.Env.t(), WAMessage.t()) :: {:ok, WAMessage.t()}
  defp handle_success_response(response, message) do
    message_id =
      response.body
      |> Jason.decode!()
      |> Map.get("data")
      |> Map.get("msgId")

    {:ok, message} =
      message
      |> Poison.encode!()
      |> Poison.decode!(as: %WAMessage{})
      |> WAMessages.update_message(%{
        bsp_id: message_id,
        bsp_status: :enqueued,
        status: :sent,
        flow: :outbound,
        sent_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    message
    |> Repo.preload([:contact])
    |> Communications.publish_data(
      :update_wa_message_status,
      message.organization_id
    )

    {:ok, message}
  end

  @spec handle_error_response(Tesla.Env.t() | map(), WAMessage.t()) :: {:error, String.t()}
  defp handle_error_response(response, message) do
    {:ok, message} =
      message
      |> Poison.encode!()
      |> Poison.decode!(as: %WAMessage{})
      |> WAMessages.update_message(%{
        bsp_status: :error,
        status: :sent,
        flow: :outbound,
        errors: build_error(response.body)
      })

    error_msg = Jason.decode!(response.body)

    Notifications.create_notification(%{
      category: "WA Group",
      message: "Error sending message: #{error_msg["message"]}",
      severity: Notifications.types().critical,
      organization_id: message.organization_id,
      entity: %{
        id: message.wa_group_id,
        body: message.body
      }
    })

    message
    |> Repo.preload([:contact])
    |> Communications.publish_data(
      :update_wa_message_status,
      message.organization_id
    )

    {:error, response.body}
  end

  @spec build_error(any()) :: map()
  defp build_error(body) do
    cond do
      is_binary(body) -> %{message: body}
      is_map(body) -> body
      true -> %{message: inspect(body)}
    end
  end
end
