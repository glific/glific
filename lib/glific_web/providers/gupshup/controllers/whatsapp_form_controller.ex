defmodule GlificWeb.Providers.Gupshup.Controllers.WhatsappFormController do
  @moduledoc """
  Controller for handling WhatsApp Business Account webhooks from Gupshup
  """

  use GlificWeb, :controller

  alias Glific.WhatsappFormResponses

  require Logger

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end

  @doc """
  Parse WhatsApp form response payload and convert that into Glific WhatsApp form response struct
  """
  @spec wa_form(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def wa_form(conn, params) do
    process_webhook(params)
    handler(conn, params, "wa_form handler")
  end

  defp process_webhook(%{"entry" => [%{"changes" => [%{"value" => %{"messages" => messages}}]}]}) do
    Enum.each(messages, &process_message/1)
  end

  @spec process_message(map()) :: any()
  defp process_message(
         %{"type" => "interactive", "interactive" => %{"type" => "nfm_reply"}} = message
       ) do
    WhatsappFormResponses.create_whatsapp_form_response(message)
  end

  defp process_message(message) do
    Logger.info("Unhandled message type: #{inspect(message)}")
  end
end
