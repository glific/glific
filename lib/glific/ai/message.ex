defmodule Glific.AI.Message do
  @moduledoc """
  One row of an agent conversation's transcript.

  `ai_messages` is simultaneously the transcript, the checkpoint, and the audit trail for its
  conversation — there is no second encoded copy stored anywhere else. `parts` holds the exact
  map produced by `Glific.AI.Codec.encode/1`; nothing else may write it. The unique
  `(conversation_id, seq)` index is what makes at-least-once step execution safe: a retried step
  inserts the same `seq`, conflicts, and `on_conflict: :nothing` (see `Glific.AI.append_message/2`)
  turns the retry into a no-op instead of a duplicate.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    AI.Conversation,
    AI.Message,
    Enums.AIMessageRole,
    Enums.AIMessageStatus,
    Partners.Organization
  }

  @required_fields [:conversation_id, :seq, :role, :parts, :organization_id]

  @optional_fields [
    :status,
    :request_id,
    :model,
    :prompt_tokens,
    :completion_tokens,
    :cached_tokens,
    :duration_ms,
    :error,
    :feedback
  ]

  @feedback_ratings ~w(like dislike)

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          conversation_id: non_neg_integer() | nil,
          conversation: Conversation.t() | Ecto.Association.NotLoaded.t() | nil,
          seq: non_neg_integer() | nil,
          role: AIMessageRole.t() | nil,
          parts: map() | nil,
          status: AIMessageStatus.t() | nil,
          request_id: String.t() | nil,
          model: String.t() | nil,
          prompt_tokens: non_neg_integer() | nil,
          completion_tokens: non_neg_integer() | nil,
          cached_tokens: non_neg_integer() | nil,
          duration_ms: non_neg_integer() | nil,
          error: String.t() | nil,
          feedback: String.t() | nil,
          organization_id: non_neg_integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "ai_messages" do
    field(:seq, :integer)
    field(:role, AIMessageRole)
    field(:parts, :map)
    field(:status, AIMessageStatus, default: :complete)
    field(:request_id, :string)
    field(:model, :string)
    field(:prompt_tokens, :integer, default: 0)
    field(:completion_tokens, :integer, default: 0)
    field(:cached_tokens, :integer, default: 0)
    field(:duration_ms, :integer)
    field(:error, :string)
    field(:feedback, :string)

    belongs_to(:conversation, Conversation)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset for appending a message row to a conversation.
  """
  @spec changeset(Message.t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:feedback, @feedback_ratings)
    |> unique_constraint([:conversation_id, :seq])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:organization_id)
  end
end
