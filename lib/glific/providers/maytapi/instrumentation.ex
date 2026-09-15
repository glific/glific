defmodule Glific.Providers.Maytapi.Instrumentation do
  @moduledoc """
  Maytapi instrumentation adapter.

  Inherits the standard provider counters (`track_send/2`, `track_receive/2`,
  `track_status/2`, `track_action/3`) from `Glific.Providers.Instrumentation`.

  Unlike `Glific.Providers.Gupshup.Instrumentation`, there is no custom
  `classify_send/2`: Maytapi has no frequency-cap style response that needs
  reclassifying out of `error`, so the inherited identity implementation
  applies and a send is recorded as it happened.

  Maytapi carries WhatsApp *group* traffic, which has no HSM/template concept,
  so every send is recorded under the default `type: "session"`.

  Note that `Glific.Providers.Instrumentation.check_inbound_staleness/0` does
  **not** cover Maytapi — it reads the `messages` table, while Maytapi group
  traffic lands in `wa_messages`, and Maytapi's low, bursty group volume would
  false-alarm a silence check.
  """

  use Glific.Providers.Instrumentation, provider: "maytapi"
end
