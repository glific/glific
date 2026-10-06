defmodule Glific.WebChannel.Rooms do
  @moduledoc """
  The open web channel conversations an organisation's contacts are holding, addressed as a group
  rather than one at a time.

  Lives here rather than in `GlificWeb` so `Glific.Partners` can close them when an admin switches
  the channel off without depending on a channel module — websocket joins, pushes and socket
  assigns — to do it. What crosses instead is a broadcast on `Glific.PubSub`, the pubsub
  `Glific.Application` already starts. That is still a `Phoenix.*` module; the difference is that
  it is transport this layer owns rather than the web layer's own machinery.
  `GlificWeb.WebChannel.RoomChannel` subscribes on join and decides what a room does about it.
  """

  @doc """
  The topic every open room for an organisation listens on.
  """
  @spec topic(non_neg_integer()) :: String.t()
  def topic(organization_id), do: "web_channel_disabled:#{organization_id}"

  @doc """
  Tell every open room for an organisation that its web channel has been switched off.
  """
  @spec close_all(non_neg_integer()) :: :ok | {:error, term()}
  def close_all(organization_id),
    do: Phoenix.PubSub.broadcast(Glific.PubSub, topic(organization_id), :web_channel_disabled)
end
