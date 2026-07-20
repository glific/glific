defmodule Glific.Providers.Maytapi.ResponseHandler do
  @moduledoc """
  Module for handling response from Provider end
  or Handle response for simulators
  """

  alias Glific.{
    Communications,
    Notifications,
    Providers.Maytapi.Instrumentation,
    Repo,
    WAGroup.WAMessage,
    WAMessages
  }

  require Logger

  @default_tesla_error """
  {\"success\":false,\"message\":\"Error sending message due to network issues or maytapi Outage\"}
  """

  # Tesla error reasons that represent a timed-out send (kept distinct from hard
  # errors so timeouts get their own AppSignal bucket).
  @timeout_reasons [:timeout, :closed_timeout, :closed]

  @doc false
  @spec handle_response({:ok, Tesla.Env.t()}, WAMessage.t() | {:error, any()}) ::
          :ok | {:error, String.t()}
  def handle_response({:ok, response}, message) do
    case response do
      %Tesla.Env{status: status} when status in 200..299 ->
        track_send(:success, message)
        handle_success_response(response, message)

      # Not authorized, Job succeeded, we should return an ok, so we don't retry
      %Tesla.Env{status: status} when status in 400..499 ->
        track_send(:error, message)
        handle_error_response(response, message)
        :ok

      _ ->
        track_send(:error, message)
        handle_error_response(response, message)
    end
  end

  # Sending default error when API Client call fails for some reason
  def handle_response(error, message) do
    track_send(send_outcome(error), message)

    # Adding log when API Client fails
    Logger.info(
      "Error calling API Client for org_id: #{message["organization_id"]} error: #{Glific.SafeLog.safe_inspect(error)}"
    )

    default_error =
      Jason.decode!(@default_tesla_error)
      |> put_in(["error"], Glific.SafeLog.safe_inspect(error))

    handle_error_response(%{body: Jason.encode!(default_error)}, message)
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
      true -> %{message: Glific.SafeLog.safe_inspect(body)}
    end
  end

  # Every path through `Glific.Providers.Maytapi.WAWorker` funnels into exactly
  # one `handle_response/2` call, so tracking here records one send per message
  # — the final outcome. A send that fails and is then rescued by the worker's
  # phone-failover retry counts only as the retry's outcome; the failover event
  # itself is already tracked by `Glific.Providers.Maytapi.Sender`.
  @spec track_send(Glific.Providers.Instrumentation.send_status(), WAMessage.t() | map() | any()) ::
          :ok
  defp track_send(status, message),
    do: Instrumentation.track_send(status, organization_id: organization_id(message))

  @spec send_outcome(any()) :: Glific.Providers.Instrumentation.send_status()
  defp send_outcome({:error, reason}) when reason in @timeout_reasons, do: :timeout
  defp send_outcome(_error), do: :error

  # The send-time message is the Oban-serialised minimal map (string keys), but
  # be tolerant of an atom-keyed WAMessage struct/map too.
  @spec organization_id(any()) :: non_neg_integer() | nil
  defp organization_id(message) when is_map(message),
    do: Map.get(message, "organization_id") || Map.get(message, :organization_id)

  defp organization_id(_message), do: nil

  @doc """
  Classify a Maytapi response as a phone-level error (eligible for retry
  via `Glific.Providers.Maytapi.Sender.pick_for_send/2` with the failed
  phone excluded).

  Returns true when:
  - status is 5xx (server-side; likely the phone's Maytapi instance is
    misbehaving), or
  - status is 4xx and the response body's `message` mentions phone,
    device, instance, or session — Maytapi surfaces phone-disconnect /
    not-active errors this way.

  Returns false for 2xx responses, malformed bodies, and 4xx errors that
  look like client problems (bad payload, rate limit) — retrying with a
  different phone wouldn't help those.
  """
  @spec phone_level_error?({:ok, Tesla.Env.t()} | term()) :: boolean()
  def phone_level_error?({:ok, %Tesla.Env{status: status}}) when status in 500..599, do: true

  def phone_level_error?({:ok, %Tesla.Env{status: status, body: body}})
      when status in 400..499 do
    case Jason.decode(body) do
      {:ok, %{"message" => message}} when is_binary(message) ->
        String.match?(String.downcase(message), ~r/phone|device|instance|session/)

      _ ->
        false
    end
  end

  def phone_level_error?(_), do: false
end
