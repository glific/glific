defmodule Glific.Flows.Webhooks.Sync do
  @moduledoc """
  `use` macro for synchronous flow webhooks — ones that return immediately
  and don't park the flow waiting on a Kaapi callback.

  Authors only write `call/2`. Failure reporting and latency telemetry are
  added by `Glific.Flows.Webhooks.Dispatcher`, not by this macro, so unit
  tests of `call/2` see raw return values.

  ## Example

      defmodule Glific.Flows.Webhooks.Geolocation do
        use Glific.Flows.Webhooks.Sync, name: "geolocation"

        @impl true
        def call(%{"lat" => lat, "long" => long}, _ctx) do
          # ... return a map ...
        end
      end
  """

  @doc """
  Injects the default sync webhook implementation into the caller.

  Requires `:name` in `opts` and defines `name/0` and `mode/0`.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    webhook_name = Keyword.fetch!(opts, :name)

    quote do
      @behaviour Glific.Flows.Webhooks.Behaviour

      @webhook_name unquote(webhook_name)

      @doc "Returns the webhook name used in flow JSON URLs."
      @spec name() :: String.t()
      @impl true
      def name, do: @webhook_name

      @doc "Marks this webhook as synchronous."
      @spec mode() :: :sync
      @impl true
      def mode, do: :sync
    end
  end
end
