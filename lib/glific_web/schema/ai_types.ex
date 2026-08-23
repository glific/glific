defmodule GlificWeb.Schema.AITypes do
  @moduledoc """
  GraphQL surface for the in-Glific AI agent runtime: dispatching a skill run
  (`startAiRequest`), resolving a propose→confirm gate (`resolveAiRequest`), cancelling an
  in-flight run (`cancelAiRequest`), the `aiConversations`/`aiConversation`/`aiMessages` reads
  that rebuild a transcript after a lost subscription, and the `aiRequestEvent` subscription
  that streams a run's progress.

  Per-skill data (the `input` a skill validates, and the `payload` an event carries) rides on
  the generic `:json` scalar rather than a typed object, so this schema does not change when a
  skill is added — see `Glific.AI.Skill` and `Glific.AI.Publisher`.
  """

  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.{Authorize, RequireFeatureFlag}

  object :ai_conversation do
    field :id, :id
    field :skill, :string
    field :title, :string
    field :status, :string
    field :active_request_id, :string
    field :active_status, :string
    field :step_count, :integer
    field :max_steps, :integer

    @desc "Opaque token to pass back to resolveAiRequest. Present only while active_status is
    awaiting_confirmation; exposed here (scoped to the conversation's owner) so a client that
    reconnects mid-gate can still resolve it."
    field :gate_token, :string
    field :gate_expires_at, :datetime
    field :pending_proposal, :json
    field :last_error, :json
    field :token_count, :integer
    field :last_message_at, :datetime

    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :user, :user do
      resolve(dataloader(Repo))
    end

    field :organization, :organization do
      resolve(dataloader(Repo))
    end
  end

  object :ai_conversation_result do
    field :conversation, :ai_conversation
    field :errors, list_of(:input_error)
  end

  object :ai_message do
    field :id, :id
    field :conversation_id, :id
    field :seq, :integer
    field :role, :string

    @desc "The Glific.AI.Codec-encoded ReqLLM message: the exact transcript row, riding on the
    generic :json scalar."
    field :parts, :json

    field :status, :string
    field :request_id, :string
    field :model, :string
    field :prompt_tokens, :integer
    field :completion_tokens, :integer
    field :cached_tokens, :integer
    field :duration_ms, :integer
    field :error, :string

    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  @desc "Ack for a dispatch or state-flip mutation on an AI request. `request_id` correlates
  the ack with the events this run publishes over the aiRequestEvent subscription."
  object :ai_request_ack do
    field :request_id, :string
    field :conversation_id, :id
    field :status, :string
    field :errors, list_of(:input_error)
  end

  @desc "One envelope on the aiRequestEvent subscription. event is one of: queued, delta,
  message, final, proposal, error. seq is present on delta/message. payload carries the
  event's per-skill data on the generic :json scalar."
  object :ai_request_event do
    field :event, :string
    field :request_id, :string
    field :conversation_id, :id
    field :seq, :integer
    field :payload, :json
    field :errors, list_of(:input_error)
  end

  @desc "Filtering options for AI conversations"
  input_object :ai_conversation_filter do
    @desc "Match the skill name"
    field :skill, :string

    @desc "Match the conversation status (active | archived)"
    field :status, :string
  end

  input_object :start_ai_request_input do
    @desc "The Glific.AI.Skill name to run, as registered in Glific.AI.Skill.Registry"
    field :skill, non_null(:string)

    @desc "Continue an existing conversation instead of starting a new one. Must have been
    created under the same skill."
    field :conversation_id, :id

    @desc "The skill-specific input, validated by the skill's validate_input/1"
    field :input, non_null(:json)
  end

  object :ai_queries do
    @desc "Get a specific AI conversation by id, scoped to the caller"
    field :ai_conversation, :ai_conversation_result do
      arg(:id, non_null(:id))
      middleware(Authorize, :staff)
      resolve(&Resolvers.AI.ai_conversation/3)
    end

    @desc "List the caller's AI conversations, most recently updated first by default"
    field :ai_conversations, list_of(:ai_conversation) do
      arg(:filter, :ai_conversation_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.AI.ai_conversations/3)
    end

    @desc "List a conversation's messages in seq order, scoped to the caller"
    field :ai_messages, list_of(:ai_message) do
      arg(:conversation_id, non_null(:id))
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.AI.ai_messages/3)
    end
  end

  object :ai_mutations do
    @desc "Dispatch a skill run. Acks immediately with status queued; the run itself proceeds
    on Glific.AI.StepWorker and is watched via the aiRequestEvent subscription."
    field :start_ai_request, :ai_request_ack do
      arg(:input, non_null(:start_ai_request_input))
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:is_ai_runtime_enabled, "AI Runtime"})
      resolve(&Resolvers.AI.start_ai_request/3)
    end

    @desc "Resolve a pending propose→confirm gate. A wrong or expired gate_token does not
    resolve the gate."
    field :resolve_ai_request, :ai_request_ack do
      arg(:conversation_id, non_null(:id))
      arg(:gate_token, non_null(:string))
      arg(:decision, non_null(:string))
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:is_ai_runtime_enabled, "AI Runtime"})
      resolve(&Resolvers.AI.resolve_ai_request/3)
    end

    @desc "Cancel an in-flight AI request"
    field :cancel_ai_request, :ai_request_ack do
      arg(:conversation_id, non_null(:id))
      middleware(Authorize, :staff)
      middleware(RequireFeatureFlag, {:is_ai_runtime_enabled, "AI Runtime"})
      resolve(&Resolvers.AI.cancel_ai_request/3)
    end
  end

  object :ai_subscriptions do
    @desc "Streams queued/delta/message/final/proposal/error events for the caller's AI
    requests within organization_id."
    field :ai_request_event, :ai_request_event do
      arg(:organization_id, non_null(:id))

      config(&subscription_topic/2)
    end
  end

  @doc false
  @spec subscription_topic(map(), map()) :: {:ok, keyword()} | {:error, String.t()}
  def subscription_topic(args, %{context: %{current_user: user}}) do
    if args.organization_id == Integer.to_string(user.organization_id) do
      {:ok, [topic: "#{user.organization_id}:#{user.id}"]}
    else
      {:error, "Auth Credentials mismatch"}
    end
  end
end
