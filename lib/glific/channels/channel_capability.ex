defmodule Glific.Channels.ChannelCapability do
  @moduledoc """
  Declares which message channel (`"web"`, `"whatsapp"`, …) can render which
  channel-neutral capability.

  Introduced for Custom UI messages: everything about `:custom_ui` is named and gated
  channel-neutrally from day one — enum values, this module — even though only the web
  channel renders it in v0. A future channel (RCS, Telegram, …) adds one declaration here,
  never a rename, migration, or flow change. Replaces hardcoded `channel == "web"` checks for
  capabilities that are conceptually about *what a channel can render*, not *is this the web
  channel*.
  """

  # capability => set of channels that support it
  @capabilities %{
    custom_ui: MapSet.new(["web"])
  }

  @doc """
  Whether `channel` supports `capability`.

  ## Examples

      iex> Glific.Channels.ChannelCapability.supports?("web", :custom_ui)
      true

      iex> Glific.Channels.ChannelCapability.supports?("whatsapp", :custom_ui)
      false

      iex> Glific.Channels.ChannelCapability.supports?("web", :unknown_capability)
      false
  """
  @spec supports?(String.t() | nil, atom()) :: boolean()
  def supports?(channel, capability) do
    @capabilities
    |> Map.get(capability, MapSet.new())
    |> MapSet.member?(channel)
  end
end
