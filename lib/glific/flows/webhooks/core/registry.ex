defmodule Glific.Flows.Webhooks.Registry do
  @moduledoc """
  Maps a webhook's name string (as it appears in flow JSON URLs) to the
  module that implements `Glific.Flows.Webhooks.Behaviour` for it.

  Migration is incremental — only webhooks that have been ported live here.
  `Glific.Clients.CommonWebhook` keeps its existing per-name clauses for
  the unmigrated webhooks; once a webhook moves to this registry, its
  CommonWebhook clause shrinks to a `Dispatcher.dispatch_named/3` call.

  ## Why Registry is separate from Dispatcher

  Tests mock `Registry.lookup!` directly (via `:passthrough` mock) to swap
  the webhook module under test without touching the dispatch pipeline. If
  the routing map were inlined into Dispatcher, those mocks would have to
  target Dispatcher itself, coupling test isolation to the orchestration
  layer. The indirection preserves a clean seam for both unit tests and
  integration tests.

  ## Node URL vs. observability webhook_name

  For most webhooks `name/0` (the node URL / registry key) equals the
  observability `webhook_name` used in Kaapi `request_metadata` and AppSignal
  metrics. The two unified-llm nodes are an exception — their node URL differs
  from their observability name. Use `lookup_by_webhook_name/1` when you have
  an observability name from a Kaapi callback and need the module.
  """

  alias Glific.Flows.Webhooks

  @webhooks %{
    "geolocation" => Webhooks.Geolocation,
    "speech_to_text" => Webhooks.SpeechToText,
    "text_to_speech" => Webhooks.TextToSpeech,
    "filesearch-gpt" => Webhooks.FilesearchGpt,
    "voice-filesearch-gpt" => Webhooks.VoiceFilesearchGpt
  }

  @doc """
  Look up the module implementing `name`, or `nil` if the webhook hasn't
  been migrated yet (the caller falls back to the legacy path).
  """
  @spec lookup(String.t()) :: module() | nil
  def lookup(name), do: Map.get(@webhooks, name)

  @doc """
  Like `lookup/1` but raises if the webhook isn't registered. Use this
  from code paths that have already confirmed the webhook is migrated.
  """
  @spec lookup!(String.t()) :: module()
  def lookup!(name) do
    case lookup(name) do
      nil -> raise ArgumentError, "no webhook registered for #{inspect(name)}"
      module -> module
    end
  end

  @doc "List every webhook name registered so far. Used by tests."
  @spec names() :: [String.t()]
  def names, do: Map.keys(@webhooks)

  @doc """
  Returns the node-URL strings for all registered async webhooks (those whose
  `mode/0` returns `:async`). Used by `Glific.Flows.Action` to route async
  FUNCTION nodes through `Dispatcher.dispatch_async/3`, and by
  `Glific.Flows.FlowContext` to identify async webhook nodes for timeout
  reporting.
  """
  @spec async_urls() :: [String.t()]
  def async_urls do
    @webhooks
    |> Enum.filter(fn {_url, mod} -> mod.mode() == :async end)
    |> Enum.map(fn {url, _mod} -> url end)
  end

  @doc """
  Finds the async webhook module whose `webhook_name/0` matches `webhook_name`.

  Used by `FlowResumeController` to route a Kaapi callback to the correct
  module's `handle_resume/2`. Returns `nil` if no registered async module has
  that observability name (the caller falls back to the default behaviour).
  """
  @spec lookup_by_webhook_name(term()) :: module() | nil
  def lookup_by_webhook_name(webhook_name) when is_binary(webhook_name) do
    @webhooks
    |> Enum.find_value(fn {_url, mod} ->
      if mod.mode() == :async and resolve_webhook_name(mod) == webhook_name do
        mod
      end
    end)
  end

  # Callbacks whose payload carries no `webhook_name` (e.g. the STT/TTS/filesearch
  # Kaapi callbacks) pass `nil` here. Fall back to nil so callers use the parsed
  # response unchanged rather than crashing on a FunctionClauseError.
  def lookup_by_webhook_name(_webhook_name), do: nil

  # Safely resolves a module's webhook_name/0; falls back to name/0 for modules
  # that don't export webhook_name/0 (e.g. the sync Geolocation module).
  # Code.ensure_loaded? is required because function_exported?/3 returns false for a
  # not-yet-loaded module, which would make lookup match on name/0 instead.
  @spec resolve_webhook_name(module()) :: String.t()
  defp resolve_webhook_name(mod) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :webhook_name, 0) do
      mod.webhook_name()
    else
      mod.name()
    end
  end
end
