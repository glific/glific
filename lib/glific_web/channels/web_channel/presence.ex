defmodule GlificWeb.WebChannel.Presence do
  @moduledoc """
  Tracks which web-channel contacts currently have a socket open, so the staff inbox can show
  "online" where a WhatsApp conversation would show its 24 hour session window.

  Tracked under a per-organization topic rather than the per-contact socket topic, so answering
  "is this contact online" is a map lookup and does not require joining anything.

  This is ephemeral, node-local state that Phoenix synchronises across a connected cluster. It is
  never persisted and must never be reported on — a contact whose browser was closed without a
  clean disconnect stays listed until the socket times out.
  """

  use Phoenix.Presence,
    otp_app: :glific,
    pubsub_server: Glific.PubSub

  @doc """
  Track the contact holding this socket as online for its organization.
  """
  @spec track_contact(pid(), non_neg_integer(), non_neg_integer()) ::
          {:ok, binary()} | {:error, any()}
  def track_contact(channel_pid, organization_id, contact_id),
    do: track(channel_pid, topic(organization_id), to_string(contact_id), %{})

  @doc """
  Whether a contact currently has at least one web-channel socket open.
  """
  # `get_by_key/2` rather than `list/1`: the latter builds the whole organization's presence map
  # to answer a question about one contact, which a contact list would then repeat per row.
  @spec online?(non_neg_integer(), non_neg_integer()) :: boolean()
  def online?(organization_id, contact_id),
    do: organization_id |> topic() |> get_by_key(to_string(contact_id)) != []

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
  end

  @spec topic(non_neg_integer()) :: String.t()
  defp topic(organization_id), do: "web_channel_presence:#{organization_id}"
end
