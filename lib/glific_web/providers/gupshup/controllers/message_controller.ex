defmodule GlificWeb.Providers.Gupshup.Controllers.MessageController do
  @moduledoc """
  Dedicated controller to handle different types of inbound message form Gupshup
  """

  use GlificWeb, :controller

  alias Glific.{
    Communications,
    Providers.Gupshup
  }

  @simulater_phone "9876543210"

  @doc false
  @spec handler(Plug.Conn.t(), map(), String.t()) :: Plug.Conn.t()
  def handler(conn, _params, _msg) do
    json(conn, nil)
  end

  @doc """
  Proxy text message from simulator to make it optin
  """
  @spec text(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def text(
        conn,
        %{
          "payload" => %{
            "payload" => %{"text" => "proxy"},
            "sender" => %{"name" => "Simulator", "phone" => @simulater_phone}
          }
        } = params
      ) do
    timestamp = DateTime.utc_now()

    @simulater_phone
    |> Glific.Contacts.contact_opted_in(conn.assigns[:organization_id], timestamp)

    params["payload"]["payload"]["text"]
    |> put_in("proxy message to optin simulator")
    |> Gupshup.Message.receive_text()
    |> Map.put(:organization_id, conn.assigns[:organization_id])
    |> Communications.Message.receive_message()

    handler(conn, params, "text handler")
  end

  @doc """
  Parse text message payload and convert that into Glific message struct
  """
  def text(conn, params) do
    params
    |> Gupshup.Message.receive_text()
    |> Map.put(:organization_id, conn.assigns[:organization_id])
    |> Communications.Message.receive_message()

    handler(conn, params, "text handler")
  end

  @doc """
  Callback for gupshup image images
  """
  @spec image(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def image(conn, params), do: media(conn, params, :image)

  @doc """
  Callback file gupshup image images
  """
  @spec file(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def file(conn, params), do: media(conn, params, :document)

  @doc """
  Callback audio gupshup image images
  """
  @spec audio(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def audio(conn, params), do: media(conn, params, :audio)

  @doc """
  Callback video gupshup image images
  """
  @spec video(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def video(conn, params), do: media(conn, params, :video)

  @doc false
  # Handle Gupshup media message and convert them into Glific Message struct
  @spec media(Plug.Conn.t(), map(), atom()) :: Plug.Conn.t()
  defp media(conn, params, type) do
    params
    |> Gupshup.Message.receive_media()
    |> Map.put(:organization_id, conn.assigns[:organization_id])
    |> Communications.Message.receive_message(type)

    handler(conn, params, "media handler")
  end

  @doc false
  # Handle Gupshup location message and convert them into Glific Message struct
  @spec location(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def location(conn, params) do
    params
    |> Gupshup.Message.receive_location()
    |> Map.put(:organization_id, conn.assigns[:organization_id])
    |> Communications.Message.receive_message(:location)

    handler(conn, params, "location handler")
  end
end
