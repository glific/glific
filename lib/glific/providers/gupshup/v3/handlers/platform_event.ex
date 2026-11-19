defmodule Glific.Providers.Gupshup.V3.Handlers.PlatformEvent do
  @moduledoc """
  Receives a Gupshup V3 platform-event change (e.g. a connectivity check). These carry
  no app or message data, so they are only counted.
  """

  @behaviour Glific.Providers.Gupshup.V3.Handler

  alias Glific.Providers.Gupshup.Instrumentation

  @impl true
  @spec handle(map(), non_neg_integer()) :: :ok
  def handle(value, organization_id),
    do: Instrumentation.track_platform_event(value["type"] || "unknown", organization_id)
end
