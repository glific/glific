defmodule Glific.AI.Event do
  @moduledoc """
  A single step taken while answering a question.

  Append-only: rows are never rewritten. Reloading a conversation's events in
  `step` order rebuilds the context sent to the model, which is how a follow-up
  question keeps what came before.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    AI.Conversation,
    AI.Message,
    Enums.GlificAIEventType,
    Partners.Organization
  }

  @required_fields [:message_id, :conversation_id, :organization_id, :step, :type]
  @optional_fields [:content, :data, :tool_call_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          step: non_neg_integer | nil,
          type: GlificAIEventType.t() | nil,
          content: String.t() | nil,
          data: map() | nil,
          tool_call_id: String.t() | nil,
          message_id: non_neg_integer | nil,
          message: Message.t() | Ecto.Association.NotLoaded.t() | nil,
          conversation_id: non_neg_integer | nil,
          conversation: Conversation.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "glific_ai_events" do
    field :step, :integer
    field :type, GlificAIEventType
    field :content, :string
    field :data, :map, default: %{}
    field :tool_call_id, :string

    belongs_to :message, Message
    belongs_to :conversation, Conversation
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Standard changeset pattern we use for all data types"
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:step, greater_than: 0)
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint([:message_id, :step])
  end
end
