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
  """

  alias Glific.Flows.Webhooks

  @webhooks %{
    "create_certificate" => Webhooks.CreateCertificate,
    "detect_language" => Webhooks.DetectLanguage,
    "geolocation" => Webhooks.Geolocation,
    "nmt_tts_with_bhasini" => Webhooks.NmtTtsWithBhasini,
    "send_wa_group_poll" => Webhooks.SendWaGroupPoll,
    "speech_to_text_with_bhasini" => Webhooks.SpeechToTextWithBhasini,
    "text_to_speech_with_bhasini" => Webhooks.TextToSpeechWithBhasini
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
end
