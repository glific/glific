defmodule Glific.RateLimit do
  @moduledoc """
  The single place every rate limit in Glific is checked, so that no breach goes uncounted.

  Every limit is named, and the name is both its configuration key and the tag it reports under.
  The configuration is the only place a limit's size is written down — callers name a limit and a
  bucket, never a fallback:

      config :glific, :rate_limit_web_channel_upload_contact, scale_ms: 60_000, count: 6

      RateLimit.check(:rate_limit_web_channel_upload_contact, "...upload:\#{contact_id}")

  A missing or malformed entry raises rather than silently applying some default, because a limit
  that quietly stops limiting is worse than one that fails loudly.

  Names are grouped by the surface they guard: `rate_limit_api_*` for the staff and provider API,
  `rate_limit_web_channel_*` for the browser-based web channel.

  A breach emits `[:glific, :rate_limit, :exceeded]` telemetry and increments the AppSignal
  counter `rate_limit_exceeded`, tagged with the limit's name. Only the name is reported, never
  the bucket key — keys carry addresses, phone numbers and contact ids, which would both leak
  into metrics and blow up tag cardinality.
  """

  require Logger

  @telemetry_event [:glific, :rate_limit, :exceeded]

  @doc """
  Count one request against a named limit.
  """
  @spec check(atom(), String.t()) :: :ok | {:error, :rate_limited}
  def check(name, key) do
    config = Application.fetch_env!(:glific, name)
    scale_ms = Keyword.fetch!(config, :scale_ms)
    count = Keyword.fetch!(config, :count)

    case ExRated.check_rate(key, scale_ms, count) do
      {:ok, _count} -> :ok
      {:error, _limit} -> exceeded(name, count, scale_ms)
    end
  end

  @spec exceeded(atom(), pos_integer(), pos_integer()) :: {:error, :rate_limited}
  defp exceeded(name, count, scale_ms) do
    tags = %{limit: to_string(name)}

    :telemetry.execute(@telemetry_event, %{count: 1, limit: count, scale_ms: scale_ms}, tags)
    Appsignal.increment_counter("rate_limit_exceeded", 1, tags)
    Logger.info("Rate limit exceeded: #{name}")

    {:error, :rate_limited}
  end
end
