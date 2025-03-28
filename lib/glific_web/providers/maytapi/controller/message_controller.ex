defmodule GlificWeb.Providers.Maytapi.Controllers.MessageController do
  @moduledoc """
  Dedicated controller to handle different types of inbound message from maytapi
  """

  use GlificWeb, :controller

  alias Glific.{
    Communications,
    Providers.Maytapi
  }

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    conn
    |> Plug.Conn.send_resp(200, "")
    |> Plug.Conn.halt()
  end

  @doc """
  Parse text message payload and convert that into Glific message struct
  """
  @spec text(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def text(conn, params) do
    params
    |> Maytapi.Message.receive_text()
    |> update_message_params(conn.assigns[:organization_id], params)
    |> Communications.GroupMessage.receive_message()

    handler(conn, params, "text handler")
  end

  @doc """
  Callback for maytapi image type
  """
  @spec image(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def image(conn, params), do: media(conn, params, :image)

  @doc """
  Callback for maytapi document type
  """
  @spec document(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def document(conn, params), do: media(conn, params, :document)

  @doc """
  Callback for maytapi audio type
  """
  @spec audio(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def audio(conn, params), do: media(conn, params, :audio)

  @doc """
  Callback for maytapi video type
  """
  @spec video(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def video(conn, params), do: media(conn, params, :video)

  @doc """
  Callback for maytapi sticker image
  """
  @spec sticker(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sticker(conn, params), do: media(conn, params, :sticker)

  @doc """
  Callback for maytapi poll message
  """
  @spec poll(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def poll(conn, params) do
    params
    |> Maytapi.Message.receive_poll()
    |> update_message_params(conn.assigns[:organization_id], params)
    |> Communications.GroupMessage.receive_message(:poll)

    handler(conn, params, "poll handler")
  end

  @doc """
  Callback for maytapi location message
  """
  @spec location(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def location(conn, params) do
    params
    |> Maytapi.Message.receive_location()
    |> update_message_params(conn.assigns[:organization_id], params)
    |> Communications.GroupMessage.receive_message(:location)

    handler(conn, params, "location handler")
  end

  @doc false
  # Handle maytapi media message and convert them into Glific Message struct
  @spec media(Plug.Conn.t(), map(), atom()) :: Plug.Conn.t()
  defp media(conn, params, type) do
    params
    |> Maytapi.Message.receive_media()
    |> update_message_params(conn.assigns[:organization_id], params)
    |> Communications.GroupMessage.receive_message(type)

    handler(conn, params, "media handler")
  end

  @spec update_message_params(map(), non_neg_integer(), map()) :: map()
  defp update_message_params(
         message_payload,
         org_id,
         params
       ) do
    message_payload
    |> Map.put(:organization_id, org_id)
    |> Map.put(:bsp_id, params["message"]["id"])
    |> Map.put(:wa_group_bsp_id, params["conversation"])
    |> Map.put(:group_name, params["conversation_name"])
    |> Map.put(:receiver, params["receiver"])
    |> Map.put(:is_dm, direct_message?(params["conversation"]))
    |> update_sender_details()
  end

  @spec update_sender_details(map()) :: map()
  defp update_sender_details(message_params),
    do: put_in(message_params, [:sender, :contact_type], "WA")

  @spec direct_message?(String.t() | nil) :: boolean()
  defp direct_message?(conversation_id) when conversation_id in ["", nil], do: true
  defp direct_message?(conversation_id), do: String.ends_with?(conversation_id, "c.us")
end
