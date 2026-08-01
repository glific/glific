defmodule GlificWeb.WebChannel.MessageSerializer do
  @moduledoc """
  Single source of truth for the wire shape of a web-channel message.

  Used by both the live broadcast path (`Glific.Providers.Web.Message`) and the history
  replies (`GlificWeb.WebChannel.RoomChannel` join/load_more), so a message looks identical
  whether it arrives live over the socket or is re-fetched when the browser reloads. Keeping
  these in lock-step matters for interactive messages: a divergence would render buttons live
  but drop them on refresh.
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
