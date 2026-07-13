defmodule Glific.Flows.Webhooks.Sync do
  @moduledoc """
  `use` macro for synchronous flow webhooks (return immediately, don't park the flow). Authors
  write only `call/2`, returning `{:ok, value}` or a typed `{:error, ErrorType.t(), message}`
  (`:unknown` when the node can't judge the failure); the `Dispatcher` adds reporting, telemetry
  and result translation. Injects `name/0` and `mode/0`.
  """

  defmacro __using__(opts) do
    webhook_name = Keyword.fetch!(opts, :name)

    quote do
      @behaviour Glific.Flows.Webhooks.Behaviour

      @webhook_name unquote(webhook_name)

      @spec name() :: String.t()
      @impl true
      def name, do: @webhook_name

      @spec mode() :: :sync
      @impl true
      def mode, do: :sync
    end
  end
end
