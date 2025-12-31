defmodule GlificWeb.MetaController do
  @moduledoc """
  Handles Meta WhatsApp webhook verification and Form error events.
  Logs all Form errors to AppSignal.
  """

  use GlificWeb, :controller

  alias Glific.Flows.Webhook.Error
  alias Glific.Repo

  require Logger

  @verify_token "glific_webhook_secret"

  @doc """
  GET endpoint for Meta webhook verification.
  """
  @spec verify(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def verify(conn, params) do
    mode = params["hub.mode"]
    token = params["hub.verify_token"]
    challenge = params["hub.challenge"]

    if mode == "subscribe" && token == @verify_token do
      send_resp(conn, 200, challenge)
    else
      send_resp(conn, 403, "Forbidden")
    end
  end

  @doc """
  POST endpoint for receiving webhook events from Meta.
  """
  @spec handle_webhook(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handle_webhook(conn, params) do
    Logger.info("Received Meta webhook POST")

    process_webhook(params)

    send_resp(conn, 200, "EVENT_RECEIVED")
  end

  @spec process_webhook(map()) :: :ok
  defp process_webhook(%{"object" => "whatsapp_business_account", "entry" => entries}) do
    Logger.info("Processing Meta webhook", entries_count: length(entries))

    Enum.each(entries, fn entry ->
      waba_id = Map.get(entry, "id")

      org_id = Repo.get_organization_id()

      entry
      |> Map.get("changes", [])
      |> Enum.each(&handle_change(org_id, waba_id, &1))
    end)

    :ok
  end

  @spec handle_change(integer() | nil, String.t(), map()) :: :ok
  defp handle_change(org_id, waba_id, %{"value" => %{"event" => "CLIENT_ERROR_RATE"} = value}) do
    message = Map.get(value, "message")
    wa_form_id = Map.get(value, "flow_id")
    error_rate = Map.get(value, "error_rate")
    threshold = Map.get(value, "threshold")

    error_message = """
    #{message},
    WA_form ID: #{wa_form_id}
    Error Rate: #{error_rate}%
    Threshold: #{threshold}%
    WABA ID: #{waba_id}
    Organization ID: #{org_id}
    """

    Appsignal.send_error(
      %Error{
        message: error_message
      },
      []
    )
  end

  defp handle_change(_org_id, _waba_id, _event) do
    # handle default case. We ignore these web hooks.
    :ok
  end
end
