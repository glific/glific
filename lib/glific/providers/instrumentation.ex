defmodule Glific.Providers.Instrumentation do
  @moduledoc """
  Provider-agnostic AppSignal observability for the messaging flow.

  The single home for the success / error / timeout counters that turn BSP send,
  receive, status and HSM-sync activity into chartable, alertable metrics. Every
  metric is stamped with a `provider` tag, so Gupshup, Maytapi and any future
  provider share one implementation. `instrument_oban: false` in
  `config/runtime.exs` means none of this is captured automatically, so the
  counters are emitted explicitly from the provider send/receive/sync paths.

  ## Adding a provider

  A provider gets all the counters for free by defining a tiny module:

      defmodule Glific.Providers.Maytapi.Instrumentation do
        use Glific.Providers.Instrumentation, provider: "maytapi"
      end

  and calling `Maytapi.Instrumentation.track_send(:success, organization_id: id)`
  etc. Provider-specific behaviour — e.g. Gupshup reclassifying a frequency-capped
  4xx as `frequency_capped` instead of `error` — is a single overridden
  `classify_send/2`; the metric mechanics below never change.
  See `Glific.Providers.Gupshup.Instrumentation`.

  Metrics (all tagged with `provider`):

    * `provider_send_count` — outbound sends, tagged `status` (final, after
      classification) and `type` (`hsm` | `session`).
    * `provider_receive_count` — inbound messages, tagged `type`.
    * `provider_status_count` — delivery-status callbacks, tagged `status`.
    * `provider_action_count` — provider-specific named actions (e.g. Gupshup's
      `hsm_sync`), tagged `action` and `status` (`success` | `failure`).

  ## Platform liveness

  `check_inbound_staleness/0` is separate and deliberately NOT per-provider or
  per-organization: it is a single whole-platform uptime signal that alerts when
  *no* organization has received *any* inbound message within
  #{15} minutes.
  """

  import Ecto.Query, warn: false

  alias Glific.{Messages.Message, Repo}

  # No inbound message across the whole platform within this window is treated as
  # a platform-level outage.
  @staleness_threshold_minutes 15

  # Upper bound on how far back the staleness query scans, so a genuine outage
  # (no recent inbound) can't turn into an unbounded backward scan of `messages`.
  @inbound_lookback_hours 24

  @typedoc "Raw send outcome handed to `track_send/3` before provider classification."
  @type send_status :: :success | :error | :timeout

  @typedoc "Outcome of a provider-specific named action recorded via `track_action/4`."
  @type action_status :: :success | :failure

  @doc """
  Injects provider-scoped instrumentation helpers into the caller.

  Requires `:provider` in `opts` and defines `provider/0`, `classify_send/2`
  (overridable), and `track_send/2`, `track_receive/2`, `track_status/2`,
  `track_action/3` that delegate to this module.
  """
  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)

    quote do
      alias Glific.Providers.Instrumentation

      @provider unquote(provider)

      @doc "Returns the provider tag stamped on this module's metrics."
      @spec provider() :: String.t()
      def provider, do: @provider

      @doc """
      Reclassify a raw send outcome into the final status recorded on
      `provider_send_count`.

      `status` is the raw outcome (`:success` | `:error` | `:timeout`); `context`
      is whatever the call site passed to `track_send/2` (e.g. `%{error_code: 472}`).
      Override to add provider-specific classification.
      """
      @spec classify_send(atom(), map()) :: atom()
      def classify_send(status, _context), do: status

      defoverridable classify_send: 2

      @doc "See `Glific.Providers.Instrumentation.track_send/3`."
      @spec track_send(Instrumentation.send_status(), keyword()) :: :ok
      def track_send(status, opts \\ []),
        do: Instrumentation.track_send(__MODULE__, status, opts)

      @doc "See `Glific.Providers.Instrumentation.track_receive/3`."
      @spec track_receive(any(), non_neg_integer() | nil) :: :ok
      def track_receive(type, organization_id),
        do: Instrumentation.track_receive(__MODULE__, type, organization_id)

      @doc "See `Glific.Providers.Instrumentation.track_status/3`."
      @spec track_status(atom(), non_neg_integer() | nil) :: :ok
      def track_status(status, organization_id),
        do: Instrumentation.track_status(__MODULE__, status, organization_id)

      @doc "See `Glific.Providers.Instrumentation.track_action/4`."
      @spec track_action(String.t(), Instrumentation.action_status(), non_neg_integer() | nil) ::
              :ok
      def track_action(action, status, organization_id),
        do: Instrumentation.track_action(__MODULE__, action, status, organization_id)
    end
  end

  @doc """
  Record an outbound send. `adapter` is the provider's instrumentation module;
  `status` is the raw outcome, which the adapter's `classify_send/2` may refine
  (e.g. `:error` → `:frequency_capped`).

  Options are also passed to `classify_send/2` as context, and used for tags:
    * `:is_hsm` — `true` for HSM/template sends, `false` (default) for session.
    * `:organization_id` — for the `organization_id` tag.
    * any provider-specific keys (e.g. `:error_code`) the adapter needs.
  """
  @spec track_send(module(), send_status(), keyword()) :: :ok
  def track_send(adapter, status, opts \\ []) when status in [:success, :error, :timeout] do
    Appsignal.increment_counter("provider_send_count", 1, %{
      provider: adapter.provider(),
      status: to_string(adapter.classify_send(status, Map.new(opts))),
      type: message_type(Keyword.get(opts, :is_hsm, false)),
      organization_id: org_tag(Keyword.get(opts, :organization_id))
    })

    :ok
  end

  @doc """
  Record an inbound message. `type` is a short label for the message kind
  (e.g. `"text handler"`).
  """
  @spec track_receive(module(), any(), non_neg_integer() | nil) :: :ok
  def track_receive(adapter, type, organization_id) do
    Appsignal.increment_counter("provider_receive_count", 1, %{
      provider: adapter.provider(),
      type: to_string(type),
      organization_id: org_tag(organization_id)
    })

    :ok
  end

  @doc """
  Record a delivery-status callback (`:enqueued`, `:sent`, `:delivered`,
  `:read`, `:error`).
  """
  @spec track_status(module(), atom(), non_neg_integer() | nil) :: :ok
  def track_status(adapter, status, organization_id) do
    Appsignal.increment_counter("provider_status_count", 1, %{
      provider: adapter.provider(),
      status: to_string(status),
      organization_id: org_tag(organization_id)
    })

    :ok
  end

  @doc """
  Record the outcome of a provider-specific named action (`:success` or
  `:failure`) — for actions the base framework doesn't model, e.g. Gupshup's HSM
  template sync as `track_action("hsm_sync", ...)`. `action` is a short,
  stable label used as the metric's `action` tag.
  """
  @spec track_action(module(), String.t(), action_status(), non_neg_integer() | nil) :: :ok
  def track_action(adapter, action, status, organization_id)
      when status in [:success, :failure] do
    Appsignal.increment_counter("provider_action_count", 1, %{
      provider: adapter.provider(),
      action: action,
      status: Atom.to_string(status),
      organization_id: org_tag(organization_id)
    })

    :ok
  end

  @doc """
  Platform-wide inbound liveness check, run once (not per-organization) from
  `Glific.Jobs.MinuteWorker`.

  Looks at the most recent inbound message across *all* organizations and sets a
  `platform_seconds_since_last_inbound` gauge. When that gap exceeds the
  #{@staleness_threshold_minutes}-minute threshold — i.e. the whole platform has
  gone silent — it increments `platform_inbound_stale` so the outage is countable
  and logs a warning. A single quiet organization never trips it.
  """
  @spec check_inbound_staleness :: :ok
  def check_inbound_staleness do
    seconds = seconds_since_last_inbound()

    Appsignal.set_gauge("platform_seconds_since_last_inbound", seconds, %{})

    maybe_flag_staleness(seconds)
  end

  # --- private ----------------------------------------------------------------

  @spec message_type(boolean()) :: String.t()
  defp message_type(true), do: "hsm"
  defp message_type(_is_hsm), do: "session"

  @spec org_tag(non_neg_integer() | nil) :: String.t()
  defp org_tag(nil), do: "unknown"
  defp org_tag(organization_id), do: to_string(organization_id)

  @spec maybe_flag_staleness(non_neg_integer()) :: :ok
  defp maybe_flag_staleness(seconds) when seconds >= @staleness_threshold_minutes * 60 do
    Appsignal.increment_counter("platform_inbound_stale", 1, %{})

    Glific.log_error(
      "Platform inbound staleness: no organization has received a message in #{div(seconds, 60)} minutes"
    )

    :ok
  end

  defp maybe_flag_staleness(_seconds), do: :ok

  # Seconds since the most recent inbound message across every organization. When
  # nothing arrived within the lookback window the platform is (at least) that
  # stale, so we clamp to the window rather than scanning the whole table.
  @spec seconds_since_last_inbound :: non_neg_integer()
  defp seconds_since_last_inbound do
    cutoff = DateTime.add(DateTime.utc_now(), -@inbound_lookback_hours * 3600, :second)

    last_inbound_at =
      Message
      |> where([message], message.flow == :inbound)
      |> where([message], message.inserted_at > ^cutoff)
      |> select([message], max(message.inserted_at))
      |> Repo.one(skip_organization_id: true)

    case last_inbound_at do
      nil -> @inbound_lookback_hours * 3600
      timestamp -> DateTime.diff(DateTime.utc_now(), timestamp)
    end
  end
end
