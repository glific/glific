defmodule Glific.Providers.Web.Instrumentation do
  @moduledoc """
  Web channel instrumentation adapter.

  Inherits the standard provider counters from `Glific.Providers.Instrumentation`, so web traffic
  is charted in AppSignal next to Gupshup and Maytapi under `provider: "web"`:

    * `provider_send_count` — outbound messages delivered over the socket, or failed to be marked sent.
    * `provider_receive_count` — inbound messages, tagged by message type.
    * `provider_action_count` — `otp_send` (the WhatsApp OTP went out or not), `sign_in`
      (a verified code became a session or not) and `media_upload_url` (an upload URL was signed
      or storage failed).

  The steps of the web sign-in funnel and conversation that the provider counters do not cover
  are counted in `web_channel_event_count`, tagged `event` (see `track_event/2` for the set).
  Every `otp_requested` ends as exactly one `otp_sent` or `otp_refused_*`.

  Web sessions are tracked in their own counter, `web_channel_token_count`, tagged `event`:
  `renewed`, `renew_refused_token_expired`, `renew_refused_session_expired`,
  `renew_refused_invalid`, and `expired` (an open conversation closed because its token ran out).

  A send has no delivery receipt on the web channel, so `track_status/3` is not used. User
  errors (a wrong code, an invalid phone, a rate limit) are not recorded as failures, so a
  failure count only moves when something on our side is wrong.
  """

  use Glific.Providers.Instrumentation, provider: "web"

  @token_events ~w(renewed renew_refused_token_expired renew_refused_session_expired renew_refused_invalid expired)

  @events ~w(otp_requested otp_sent otp_refused_invalid_phone otp_refused_rate_limited
              otp_refused_undeliverable otp_verified otp_verification_failed sign_in_failed
              message_sent_staff message_sent_flow opt_in_recorded media_upload_issued
              media_upload_completed)

  @doc "Record a web channel funnel or conversation event in AppSignal."
  @spec track_event(String.t(), non_neg_integer()) :: :ok
  def track_event(event, organization_id) when event in @events do
    Appsignal.increment_counter("web_channel_event_count", 1, %{
      event: event,
      organization_id: to_string(organization_id)
    })

    :ok
  end

  @doc "Record a web session token event in AppSignal."
  @spec track_token(String.t(), non_neg_integer()) :: :ok
  def track_token(event, organization_id) when event in @token_events do
    Appsignal.increment_counter("web_channel_token_count", 1, %{
      event: event,
      organization_id: to_string(organization_id)
    })

    :ok
  end
end
