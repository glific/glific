defmodule Glific.PostHog do
  @moduledoc """
  Wrapper around the posthog package for product analytics.

  distinct_id is set once per process (request) via put_distinct_id/1,
  mirroring the Logger.metadata / Repo.put_organization_id pattern.
  When distinct_id is not set (cron jobs, background tasks), capture/2 is a no-op.
  """

  @doc """
  Sets the PostHog distinct_id for the current process.
  Call this once at the start of a request (e.g. in Authorize middleware).
  """
  @spec put_distinct_id(String.t()) :: any()
  def put_distinct_id(id), do: Process.put(:posthog_distinct_id, id)

  @doc """
  Captures a PostHog event. Fire-and-forget — never blocks the caller.
  No-ops when distinct_id is not set or POSTHOG_API_KEY is not configured.
  """
  @spec capture(String.t(), map()) :: :ok
  def capture(event, properties \\ %{}) do
    distinct_id = Process.get(:posthog_distinct_id)

    params = %{}
    if distinct_id, do: Map.put(params, :distinct_id, distinct_id)

    api_key = Application.get_env(:posthog, :api_key)
    if api_key do
      Task.start(fn -> Posthog.capture(event, params) end)
    end

    :ok
  end
end
