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
      body: body(message),
      type: message.type,
      flow: message.flow,
      inserted_at: message.inserted_at,
      interactive_content: message.interactive_content,
      media: media(message)
    }
  end

  # A media message's caption lives on the media row, not `message.body`, so surface it as the
  # body — the widget renders that field as the caption, the same field it uses for a plain text
  # message and for the caption on media it sends itself.
  @spec body(Message.t()) :: String.t()
  defp body(%{body: body}) when is_binary(body) and body != "", do: body
  defp body(%{media: %{caption: caption}}) when is_binary(caption) and caption != "", do: caption
  defp body(%{body: body}) when is_binary(body), do: body
  defp body(_), do: ""

  @spec media(Message.t()) :: map() | nil
  defp media(%{media: %Ecto.Association.NotLoaded{}}), do: nil
  defp media(%{media: nil}), do: nil
  defp media(%{media: media}), do: %{url: media.url}
end
