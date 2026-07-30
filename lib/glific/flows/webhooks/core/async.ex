defmodule Glific.Flows.Webhooks.Async do
  @moduledoc """
  `use` macro for asynchronous flow webhooks (Kaapi STT/TTS, filesearch-gpt,
  voice-filesearch-gpt). These park the flow context (`is_await_result: true`) and are resumed
  by a callback to `flow_resume_controller`.

  Authors write `call/2`; the parsed callback is merged into the flow context by
  `Glific.Flows.Webhook` on resume. Override `wait_time_default/0` if the default 60s await
  window doesn't fit.
  """

  @doc """
  Injects the default async webhook implementation into the caller. Requires `:name` in `opts`.
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

      @doc "Marks this webhook as asynchronous."
      @spec mode() :: :async
      @impl true
      def mode, do: :async

      @doc "Default timeout in seconds while awaiting callback resume."
      @spec wait_time_default() :: non_neg_integer()
      @impl true
      def wait_time_default, do: 60

      @doc "Shapes the parsed callback the flow resumes on; default passes it through unchanged."
      @spec handle_callback(map(), map(), Glific.Flows.Webhooks.Behaviour.ctx()) :: map()
      @impl true
      def handle_callback(_result, response, _ctx), do: response

      @doc "Classifies a failed Kaapi callback into an ErrorType; default delegates to KaapiSupport."
      @spec classify(map()) :: Glific.Flows.Webhooks.ErrorType.t()
      @impl true
      # Fully qualified on purpose: an alias here would collide with caller modules that alias
      # Glific.ThirdParty.Kaapi as `Kaapi`.
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      def classify(result), do: Glific.Flows.Webhooks.Kaapi.classify(result)

      defoverridable wait_time_default: 0, handle_callback: 3, classify: 1
    end
  end
end
