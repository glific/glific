defmodule Glific.AI.Publisher do
  @moduledoc """
  The single `Absinthe.Subscription.publish` call site for the AI agent runtime
  (`Glific.AI.Runtime` / `Glific.AI.StepWorker`), mirroring
  `Glific.Assistants.handle_assistant_chat_callback/2`.

  Publishes to topic `"\#{conversation.organization_id}:\#{conversation.user_id}"`, read off the
  `conversation` argument rather than the current process — the sweeper and cron paths that can
  drive a run forward (retries, gate expiry) have no `current_user` in their process dictionary,
  only a conversation loaded from the database.

  ## Event vocabulary

  `:queued | :delta | :message | :final | :proposal | :error`. This topic is shared with
  `ask_glific_response` and `assistant_chat_response` (see
  `GlificWeb.Schema.AskGlificTypes`/`AssistantChatTypes`), and the frontend drops any event whose
  `request_id` doesn't match the one it is waiting on (see
  glific-frontend/src/containers/AskGlific/AskGlific.tsx:128-131) — so every envelope carries
  `request_id` when the caller has one to give, and `:delta`/`:message` also carry `seq` so the
  client knows which bubble to append streamed text to.

  ## Persistence contract

  `:delta` events are streaming previews and are **never** persisted anywhere — only `:message`,
  `:final`, `:proposal`, and `:error` correspond to a row the caller has already written to
  `ai_messages` or `ai_conversations` before publishing. A client that misses a `:delta` (a
  dropped subscription, a refresh mid-stream) has no way to recover it; the `aiConversation` and
  `aiMessages` queries only ever reconstruct the durable events.

  ## `request_id` on terminal events

  A terminal event is published *after* the transaction that cleared `active_request_id`, so the
  conversation struct in hand no longer carries it. Every caller therefore reads the request id
  off the conversation **before** its `Ecto.Multi` runs and passes it in explicitly — see
  `Glific.AI.StepWorker`'s `persist_done/4` and `fail_permanently/2`. Deriving it here from the
  conversation instead would silently publish `request_id: nil` on exactly the `:final` and
  `:error` events a waiting client is filtering for, and the client would hang rather than
  error.
  """

  alias Glific.{AI.Conversation, AskGlific.Bridge}

  @typedoc "The runtime event vocabulary carried on the `ai_request_event` subscription wire."
  @type event :: :queued | :delta | :message | :final | :proposal | :error

  @events [:queued, :delta, :message, :final, :proposal, :error]

  @doc """
  Publishes one runtime event for `conversation` to its owner's subscription topic.

  `request_id` correlates every envelope from one run and is echoed back on every event,
  including `:error` — `nil` only when the caller genuinely never had one (see "`request_id` on
  terminal events" above). `fields` may add `:seq` (expected on `:delta`/`:message`),
  `:payload` (the event's per-skill data, riding on the generic `:json` scalar so the spine does
  not change when a skill is added), and `:errors` (a list of `%{key, message}` maps, for the
  `:error` event).
  """
  @spec publish(Conversation.t(), event(), String.t() | nil, map()) :: :ok
  def publish(%Conversation{} = conversation, event, request_id, fields \\ %{})
      when event in @events and (is_binary(request_id) or is_nil(request_id)) do
    Absinthe.Subscription.publish(
      GlificWeb.Endpoint,
      envelope(conversation, event, request_id, fields),
      ai_request_event: topic(conversation)
    )

    publish_legacy(conversation, event, request_id, fields)

    :ok
  end

  # A per-skill publisher registry is more machinery than one temporary bridge deserves — the
  # generic publisher knowing about one legacy skill on purpose, until the frontend migrates and
  # this dispatch (and `Glific.AskGlific.Bridge`) can be deleted, is the smaller cost.
  @doc false
  @spec publish_legacy(Conversation.t(), event(), String.t() | nil, map()) :: :ok
  def publish_legacy(
        %Conversation{skill: "ask_glific"} = conversation,
        event,
        request_id,
        fields
      ),
      do: Bridge.publish(conversation, event, request_id, fields)

  def publish_legacy(_conversation, _event, _request_id, _fields), do: :ok

  @doc false
  @spec envelope(Conversation.t(), event(), String.t() | nil, map()) :: map()
  def envelope(%Conversation{} = conversation, event, request_id, fields) do
    %{
      event: Atom.to_string(event),
      request_id: request_id,
      conversation_id: conversation.id,
      seq: Map.get(fields, :seq),
      payload: Map.get(fields, :payload),
      errors: Map.get(fields, :errors, [])
    }
  end

  @doc false
  @spec topic(Conversation.t()) :: String.t()
  def topic(%Conversation{} = conversation),
    do: "#{conversation.organization_id}:#{conversation.user_id}"
end
