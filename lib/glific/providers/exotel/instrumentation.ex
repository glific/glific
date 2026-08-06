defmodule Glific.Providers.Exotel.Instrumentation do
  @moduledoc """
  Exotel instrumentation adapter.

  Inherits the standard provider counters from `Glific.Providers.Instrumentation`.
  Exotel carries IVR/missed-call traffic rather than WhatsApp messages, so only
  `track_action/3` applies: the opt-in callback is recorded as
  `track_action("optin", :success | :failure, organization_id)`.

  The send/receive/status counters and `classify_send/2` are inherited but unused —
  Exotel never sends or receives a message through Glific.
  """

  use Glific.Providers.Instrumentation, provider: "exotel"
end
