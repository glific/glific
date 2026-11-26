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

  A send has no delivery receipt on the web channel, so `track_status/3` is not used. User
  errors (a wrong code, an invalid phone, a rate limit) are not recorded as failures, so a
  failure count only moves when something on our side is wrong.
  """

  use Glific.Providers.Instrumentation, provider: "web"
end
