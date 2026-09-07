defmodule GlificWeb.WebChannel.Presence do
  @moduledoc """
  Tracks which web-channel contacts currently have a socket open, so the staff inbox can show
  "online" where a WhatsApp conversation would show its 24 hour session window.

  Tracked under a per-organization topic rather than the per-contact socket topic, so answering
  "is this contact online" is a map lookup and does not require joining anything.

  This is ephemeral, node-local state that Phoenix synchronises across a connected cluster. It is
  never persisted and must never be reported on — a contact whose browser was closed without a
  clean disconnect stays listed until the socket times out.

  Every function here degrades rather than raises when the tracker is not running. Presence is a
  display nicety; a conversation must not fail to open, and a contact query must not 500, because
  of it. That is not hypothetical: Phoenix's dev reloader recompiles modules without restarting
  the supervision tree, so a developer who pulls this branch into a running server gets the code
  that calls the tracker without the tracker itself, and an unguarded `track/4` raises inside
  `join/3` and takes the channel down.
  """

  use Phoenix.Presence,
    otp_app: :glific,
    pubsub_server: Glific.PubSub

  @doc """
  Track the contact holding this socket as online for its organization.
  """
  @spec track_contact(pid(), non_neg_integer(), non_neg_integer()) :: :ok
  def track_contact(channel_pid, organization_id, contact_id) do
    track(channel_pid, topic(organization_id), to_string(contact_id), %{})
    :ok
  rescue
    error -> unavailable(error, "track contact #{contact_id}", :ok)
  end

  @doc """
  Whether a contact currently has at least one web-channel socket open.
  """
  # `get_by_key/2` rather than `list/1`: the latter builds the whole organization's presence map
  # to answer a question about one contact, which a contact list would then repeat per row.
  @spec online?(non_neg_integer(), non_neg_integer()) :: boolean()
  def online?(organization_id, contact_id) do
    organization_id |> topic() |> get_by_key(to_string(contact_id)) != []
  rescue
    error -> unavailable(error, "read presence for contact #{contact_id}", false)
  end

  @doc """
  The ids of every contact in an organization with a web-channel socket open.
  """
  @spec online_contact_ids(non_neg_integer()) :: [non_neg_integer()]
  def online_contact_ids(organization_id) do
    organization_id
    |> topic()
    |> list()
    |> Map.keys()
    |> Enum.map(&String.to_integer/1)
  rescue
    error -> unavailable(error, "list online contacts", [])
  end

  # send_appsignal? false: the one way this fires in practice is a dev server that reloaded the
  # code without restarting the tree, which is a local annoyance rather than something to page on.
  @spec unavailable(Exception.t(), String.t(), any()) :: any()
  defp unavailable(error, action, fallback) do
    Glific.log_error(
      "Web channel presence unavailable, could not #{action}: " <>
        Glific.SafeLog.safe_inspect(error),
      false
    )

    fallback
  end

  @spec topic(non_neg_integer()) :: String.t()
  defp topic(organization_id), do: "web_channel_presence:#{organization_id}"
end
