defmodule Glific.Flows.Webhooks.Sync do
  @moduledoc """
  `use` macro for synchronous flow webhooks — ones that return immediately
  and don't park the flow waiting on a Kaapi callback.

  Authors only write `call/2`. Failure reporting, latency telemetry, and
  legacy result translation (`ResultTranslator.to_legacy_structure/2`) are added by
  `Glific.Flows.Webhooks.Dispatcher`, not by this macro, so unit tests of
  `call/2` see raw return values.

  ## Example

      defmodule Glific.Flows.Webhooks.Geolocation do
        use Glific.Flows.Webhooks.Sync, name: "geolocation"

        @impl true
        def call(fields, _ctx) do
          # ... return {:ok, value} or {:error, "message"} ...
        end
      end
  """

  @doc """
  Injects the default sync webhook implementation into the caller.

  Requires `:name` in `opts` and defines `name/0` and `mode/0`.
  """
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

      @doc "Classify this webhook's own failures; `nil` defers to the central engine."
      @spec error_class(map()) :: :config | :system | :transient | :stale | nil
      @impl true
      def error_class(_result), do: nil

      defoverridable error_class: 1
    end
  end
end
