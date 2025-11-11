defmodule GlificWeb.MetaController do
  @moduledoc """
  Handles Meta WhatsApp webhook verification and Flow error events.
  Logs all Flow errors to AppSignal.
  """

  use GlificWeb, :controller
  require Logger

  @doc """
  GET endpoint for Meta webhook verification.
  """
  def verify(conn, params) do
    mode = params["hub.mode"]
    token = params["hub.verify_token"]
    challenge = params["hub.challenge"]

    verify_token = "glific_webhook_secret_2024"

    if mode == "subscribe" && token == verify_token do
      send_resp(conn, 200, challenge)
    else
      send_resp(conn, 403, "Forbidden")
    end
  end
end
