defmodule GlificWeb.WebChannel.Flag do
  @moduledoc """
  Live `:web_channel_enabled` check, shared by every surface that gates on it (the OTP auth
  controller, the socket, and media upload) so the check can't drift into three copies.
  """

  alias Glific.{Flags, Partners}

  @doc """
  Whether the web channel is enabled for `organization_id`.

  Reads the flag live rather than off `organization.web_channel_enabled` — that field is only
  refreshed by `Partners.fill_cache/1`, so it reports stale once the flag is flipped without a
  cache refill (the bug #5662 shipped once already).
  """
  @spec enabled?(non_neg_integer()) :: boolean()
  def enabled?(organization_id) do
    case Partners.organization(organization_id) do
      # `organization_id` can come from a token's claimed org — an id an attacker (or an
      # over-aged/otherwise-malformed token) could name without one actually existing.
      {:error, _reason} -> false
      organization -> Flags.get_flag_enabled(:web_channel_enabled, organization)
    end
  end
end
