defmodule Glific.Providers.Gupshup.Instrumentation do
  @moduledoc """
  Gupshup instrumentation adapter.

  Inherits the standard provider counters (`track_send/2`, `track_receive/2`,
  `track_status/3`, `track_action/3`) from `Glific.Providers.Instrumentation`,
  and adds Gupshup's custom frequency-cap classification on **both** seams a cap
  can surface on:

    * `classify_send/2` — a frequency-capped 4xx in the *synchronous* send
      response is recorded as `frequency_capped` rather than `error`.
    * `classify_status/2` — a frequency-capped *asynchronous* failed delivery
      callback (where Gupshup actually reports the cap, code at
      `payload.payload.code`) is likewise recorded as `frequency_capped` on
      `provider_status_count` rather than `error`.

  Both keep throttled traffic out of the `error` bucket so it doesn't trip
  send/status-failure alerts. HSM template sync is recorded via
  `track_action("hsm_sync", ...)`.
  """

  use Glific.Providers.Instrumentation, provider: "gupshup"

  # NOTE: 472 is Gupshup's documented "Frequency Cap" code. The exact code(s) to
  # exclude are an open question on the monitoring ticket — confirm against live
  # payloads and adjust this list. Call sites and the generic framework stay
  # untouched.
  @frequency_cap_error_codes [472]

  def classify_send(:error, context) do
    if frequency_capped?(context[:error_code]), do: :frequency_capped, else: :error
  end

  def classify_send(status, context), do: super(status, context)

  # A frequency cap normally surfaces as an async failed delivery callback (the
  # send is accepted, then WhatsApp/Meta reports the cap later), so this is the
  # seam that matters in practice; `classify_send/2` above covers the rarer
  # synchronous case. Same `error_code` list drives both.
  def classify_status(:error, context) do
    if frequency_capped?(context[:error_code]), do: :frequency_capped, else: :error
  end

  def classify_status(status, context), do: super(status, context)

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
