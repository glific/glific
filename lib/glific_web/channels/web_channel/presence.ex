defmodule GlificWeb.WebChannel.Presence do
  @moduledoc """
  Tracks which web channel contacts currently have a live socket connection.

  Presence is how outbound web channel delivery decides whether to broadcast a message
  live or mark it undelivered (`Glific.Providers.Web.Message`) — the web channel does
  not do store-and-forward.
  """

  use Phoenix.Presence,
    otp_app: :glific,
    pubsub_server: Glific.PubSub
end
