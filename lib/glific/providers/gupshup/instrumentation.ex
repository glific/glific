defmodule Glific.Providers.Gupshup.Instrumentation do
  @moduledoc """
  Gupshup instrumentation adapter.

  Inherits the standard provider counters (`track_send/2`, `track_receive/2`,
  `track_status/2`, `track_hsm_sync/2`) from
  `Glific.Providers.Instrumentation.Adapter`, and adds Gupshup's one bit of
  custom classification: a frequency-capped 4xx is recorded under a
  `frequency_capped` status rather than `error`, so throttled sends don't trip
  send-failure alerts.
  """

  use Glific.Providers.Instrumentation.Adapter, provider: "gupshup"

  # NOTE: 472 is Gupshup's documented "Frequency Cap" code. The exact code(s) to
  # exclude are an open question on the monitoring ticket — confirm against live
  # payloads and adjust this list. Call sites and the generic framework stay
  # untouched.
  @frequency_cap_error_codes [472]

  @impl true
  def classify_send(:error, context) do
    if frequency_capped?(context[:error_code]), do: :frequency_capped, else: :error
  end

  def classify_send(status, _context), do: status

  @doc """
  Whether a Gupshup error code represents a frequency-capped send. Accepts the
  raw code as an integer or string.
  """
  @spec frequency_capped?(any()) :: boolean()
  def frequency_capped?(code), do: normalize_code(code) in @frequency_cap_error_codes

  @spec normalize_code(any()) :: integer() | nil
  defp normalize_code(code) when is_integer(code), do: code

  defp normalize_code(code) when is_binary(code) do
    case Integer.parse(code) do
      {int, _rest} -> int
      :error -> nil
    end
  end

  defp normalize_code(_code), do: nil
end
