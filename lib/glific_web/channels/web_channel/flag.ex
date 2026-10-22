defmodule GlificWeb.WebChannel.Flag do
  @moduledoc """
  Whether the web channel is switched on for an organization, for every surface that gates on
  it: the branding endpoint, the OTP auth controller, the socket, and media upload.

  Two switches, and both have to be on. `:web_channel_enabled` is Glific's — may this
  organization have the feature at all — and a Glific admin flips it at `/feature-flags`. An
  active `web_channel` credential is the organization's own, flipped by its admin on the
  Settings page. Without the second, an organization granted the feature but configured with
  nothing is already reachable in a browser, serving Glific's default branding under its own
  domain to anyone who finds the address.

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

  alias Glific.{Flags, Partners, Partners.Organization}

  @provider_code "web_channel"

  @doc """
  Whether the web channel is on for an organization, false for one that does not exist.

  Takes the id — which every caller reads from a JWT claim and so cannot trust — or an
  organization already loaded, for a caller that has one and should not resolve it twice.
  """
  @spec web_channel_enabled?(non_neg_integer() | Organization.t()) :: boolean()
  def web_channel_enabled?(%Organization{} = organization),
    do: Flags.get_flag_enabled(:web_channel_enabled, organization) and configured?(organization)

  def web_channel_enabled?(organization_id) do
    case Partners.organization(organization_id) do
      {:error, _reason} -> false
      organization -> web_channel_enabled?(organization)
    end
  end

  # `services` holds only ACTIVE credentials — `Partners.set_credentials/1` filters on
  # `is_active` — so the key being present is the organization's own switch being on.
  @spec configured?(Organization.t()) :: boolean()
  defp configured?(organization), do: is_map(organization.services[@provider_code])
end
