defmodule GlificWeb.WebChannel.Flag do
  @moduledoc """
  Whether the web channel is switched on for an organization, for the surfaces that gate on it:
  the OTP auth controller, the socket, and media upload.

  `lib/glific/CLAUDE.md` says not to write a per-flag wrapper around
  `Glific.Flags.get_flag_enabled/2`, and to call it inline instead. This is the exception that
  rule allows — "real extra logic beyond the flag check itself" — and the extra logic is the
  reason it exists rather than convenience or testability:

  1. **It resolves an untrusted organization id.** Every caller here takes the id from a JWT
     claim, so it can name an organization that does not exist. `Partners.organization/1`
     returns `{:error, _}` in that case and `Flags.get_flag_enabled/2` is not defensive against
     it, so the check has to handle it before asking about the flag.
  2. **It pins the live read.** Reading `organization.web_channel_enabled` instead is a bug that
     already shipped once (#5662): that virtual field is stamped only by `Partners.fill_cache/1`,
     so enabling the flag left the endpoints returning 404 until the cache expired.

  Inlining would mean repeating both at five call sites, which is where the second one drifts
  back in.
  """

  alias Glific.{Flags, Partners}

  @doc """
  Whether `:web_channel_enabled` is on for `organization_id`, false for an organization that
  does not exist.
  """
  @spec web_channel_enabled?(non_neg_integer()) :: boolean()
  def web_channel_enabled?(organization_id) do
    case Partners.organization(organization_id) do
      {:error, _reason} -> false
      organization -> Flags.get_flag_enabled(:web_channel_enabled, organization)
    end
  end
end
