defmodule Glific.Providers.Web.Message do
  @moduledoc """
  Message API layer between the application and a connected browser (the "web channel").

  Unlike the BSP providers (Gupshup, Maytapi), there is no external HTTP call and no
  store-and-forward: delivery is presence-dependent. If the browser is currently connected
  (tracked via `GlificWeb.WebChannel.Presence`), the message is broadcast live over the
  socket. If not, the message stays persisted but is marked undelivered — there is no Oban
  job to retry it later.
  """

  @behaviour Glific.Providers.MessageBehaviour

  alias Glific.Messages
  alias Glific.Messages.Message
  alias GlificWeb.WebChannel.MessageSerializer
  alias GlificWeb.WebChannel.Presence

  require Logger

  @doc false
  @spec send_text(Message.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def send_text(message, attrs), do: deliver(message, attrs)

  @doc false
  @spec send_image(Message.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def send_image(message, attrs), do: deliver(message, attrs)

  @doc false
  @spec send_audio(Message.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def send_audio(message, attrs), do: deliver(message, attrs)

  @doc false
  @spec send_video(Message.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def send_video(message, attrs), do: deliver(message, attrs)

  @doc false
  @spec send_document(Message.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def send_document(message, attrs), do: deliver(message, attrs)

  @doc false
  @spec send_sticker(Message.t(), map()) :: {:error, String.t()}
  def send_sticker(_message, _attrs),
    do: {:error, "Web channel does not support this message type"}

  @doc false
  @spec send_interactive(Message.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def send_interactive(message, attrs), do: deliver(message, attrs)

  @doc false
  @spec send_custom_ui(Message.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def send_custom_ui(message, attrs), do: deliver(message, attrs)

  # Web inbound never arrives via this provider — the browser posts it directly to
  # `GlificWeb.WebChannel.RoomChannel`, which calls `Glific.Communications.WebMessage.receive_message/2`.
  # These callbacks exist only to satisfy `Glific.Providers.MessageBehaviour`.
  @doc false
  @spec receive_text(map()) :: map()
  def receive_text(payload), do: payload

  @doc false
  @spec receive_media(map()) :: map()
  def receive_media(payload), do: payload

  @doc false
  @spec receive_location(map()) :: map()
  def receive_location(payload), do: payload

  @doc false
  @spec receive_interactive(map()) :: map()
  def receive_interactive(payload), do: payload

  @doc false
  @spec receive_billing_event(map()) :: {:ok, map()} | {:error, String.t()}
  def receive_billing_event(payload), do: {:ok, payload}

  # Broadcast live if the contact's browser is connected; otherwise persist as undelivered.
  # No Tesla/HTTP call, no Oban job — this is the entire "send" for the web channel.
  @spec deliver(Message.t(), map()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  defp deliver(message, _attrs) do
    topic = "web_channel:#{message.contact_id}"

    if connected?(topic) do
      GlificWeb.Endpoint.broadcast(topic, "new_message", MessageSerializer.serialize(message))
      Messages.update_message(message, %{status: :sent, bsp_status: :delivered})
    else
      Logger.info(
        "Web channel contact #{message.contact_id} not connected; message #{message.id} stored undelivered"
      )

      Messages.update_message(message, %{status: :sent, bsp_status: :error})
    end
  end

  @spec connected?(String.t()) :: boolean()
  defp connected?(topic), do: Presence.list(topic) != %{}
end
