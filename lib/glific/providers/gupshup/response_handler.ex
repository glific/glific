defmodule Glific.Providers.Gupshup.ResponseHandler do
  @moduledoc """
  Module for handling response from Provider end
  or Handle response for simulators
  """
  alias Glific.{
    Communications,
    Messages.Message,
    Providers.Gupshup.Instrumentation
  }

  require Logger

  # Tesla error reasons that represent a timed-out send (kept distinct from hard
  # errors so timeouts get their own AppSignal bucket).
  @timeout_reasons [:timeout, :closed_timeout, :closed]

  @doc false
  @spec handle_response({:ok, Tesla.Env.t()}, Message.t() | {:error, any()}) ::
          :ok | {:error, String.t()}
  def handle_response({:ok, response}, message) do
    case response do
      %Tesla.Env{status: status} when status in 200..299 ->
        track_send(:success, message)
        Communications.Message.handle_success_response(response, message)
        :ok

      # Not authorized, Job succeeded, we should return an ok, so we don't retry
      %Tesla.Env{status: status} when status in 400..499 ->
        track_send(:error, message, error_code: extract_error_code(response.body))
        Communications.Message.handle_error_response(response, message)
        :ok

      _ ->
        track_send(:error, message)
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
    track_send(send_outcome(error), message)

    # Adding log when API Client fails
    Logger.error(
      "Error calling API Client for org_id: #{message["organization_id"]} error: #{Glific.SafeLog.safe_inspect(error)}"
    )

    # Sending default error when API Client call fails for some reason
    err =
      Communications.Message.handle_error_response(
        %{
          body:
            put_in(
              @default_tesla_error,
              ["payload", "payload", "error"],
              Glific.SafeLog.safe_inspect(error)
            )
        },
        message
      )

    case error do
      {:error, reason} when reason in @timeout_reasons ->
        # This will kickoff oban retry mechanism for timeout related errors
        err

      _ ->
        :ok
    end
  end

  @spec send_outcome(any()) :: Glific.Providers.Instrumentation.send_status()
  defp send_outcome({:error, reason}) when reason in @timeout_reasons, do: :timeout
  defp send_outcome(_error), do: :error

  @spec track_send(
          Glific.Providers.Instrumentation.send_status(),
          Message.t() | map() | any(),
          keyword()
        ) :: :ok
  defp track_send(status, message, extra \\ []) do
    opts =
      [
        is_hsm: field(message, "is_hsm", :is_hsm) || false,
        organization_id: field(message, "organization_id", :organization_id)
      ] ++ extra

    Instrumentation.track_send(status, opts)
  end

  # The send-time message is the Oban-serialised minimal map (string keys), but
  # be tolerant of an atom-keyed Message struct/map too.
  @spec field(any(), String.t(), atom()) :: any()
  defp field(message, string_key, atom_key) when is_map(message),
    do: Map.get(message, string_key) || Map.get(message, atom_key)

  defp field(_message, _string_key, _atom_key), do: nil

  @spec extract_error_code(any()) :: any()
  defp extract_error_code(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> extract_error_code(decoded)
      {:error, _reason} -> nil
    end
  end

  defp extract_error_code(%{} = body),
    do: body["code"] || get_in(body, ["payload", "payload", "code"])

  defp extract_error_code(_body), do: nil
end
