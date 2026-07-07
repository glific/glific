defmodule Glific.Providers.Instrumentation.Adapter do
  @moduledoc """
  Mixin that turns a module into a provider instrumentation adapter.

      defmodule Glific.Providers.Maytapi.Instrumentation do
        use Glific.Providers.Instrumentation.Adapter, provider: "maytapi"
      end

  gives `track_send/2`, `track_receive/2`, `track_status/2` and
  `track_hsm_sync/2` — all tagged `provider: "maytapi"` and delegating to
  `Glific.Providers.Instrumentation` — with no further code.

  To add provider-specific classification (e.g. frequency capping) override
  `c:Glific.Providers.Instrumentation.Behaviour.classify_send/2`; see
  `Glific.Providers.Gupshup.Instrumentation`.
  """

  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)

    quote do
      @behaviour Glific.Providers.Instrumentation.Behaviour

      alias Glific.Providers.Instrumentation

      @provider unquote(provider)

      @impl Glific.Providers.Instrumentation.Behaviour
      def provider, do: @provider

      @impl Glific.Providers.Instrumentation.Behaviour
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

      @doc "See `Glific.Providers.Instrumentation.track_hsm_sync/3`."
      @spec track_hsm_sync(Instrumentation.sync_status(), non_neg_integer() | nil) :: :ok
      def track_hsm_sync(status, organization_id),
        do: Instrumentation.track_hsm_sync(__MODULE__, status, organization_id)
    end
  end
end
