defmodule GlificWeb.WebChannel.MessageSerializer do
  @moduledoc """
  Single source of truth for the wire shape of a web-channel message.

  Used by `GlificWeb.WebChannel.RoomChannel`'s join/load_more history replies, so a message
  looks the same whether it arrives live over the socket or is re-fetched on a browser reload.
  """

  alias Glific.Messages.Message

  @doc """
  Serialize a message into the map shape the web-channel socket sends to the browser.
  """
  @spec serialize(Message.t()) :: map()
  def serialize(message) do
    %{
      id: message.id,
      body: message.body,
      type: message.type,
      flow: message.flow,
      inserted_at: message.inserted_at,
      interactive_content: message.interactive_content,
      media: media(message)
    }
  end

  @spec media(Message.t()) :: map() | nil
  defp media(%{media: %Ecto.Association.NotLoaded{}}), do: nil
  defp media(%{media: nil}), do: nil
  defp media(%{media: media}), do: %{url: media.url}
end
