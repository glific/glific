defmodule Glific.AI.Conversation do
  @moduledoc """
  A single agent-run conversation: one row per chat thread, watched by the UI while a turn is
  in flight and read back to rebuild the model context via `Glific.AI.build_context/1`.

  In-flight execution state (`active_request_id`, `active_status`, `step_count`, `gate_token`,
  `pending_proposal`, `last_error`) lives on this row rather than on the Oban job, because
  `Oban.Plugins.DynamicPruner` deletes job rows five minutes after completion — this row is the
  only durable place left to watch a run or recover from a crash mid-run.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    AI.Conversation,
    AI.Message,
    Enums.AIRequestStatus,
    Partners.Organization,
    Users.User
  }

  @required_fields [:skill, :max_steps, :codec_version, :user_id, :organization_id]

  @optional_fields [
    :title,
    :status,
    :active_request_id,
    :active_status,
    :step_count,
    :gate_token,
    :gate_expires_at,
    :pending_proposal,
    :last_error,
    :token_count,
    :req_llm_version,
    :last_message_at
  ]

  @statuses ~w(active archived)

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          skill: String.t() | nil,
          title: String.t() | nil,
          status: String.t() | nil,
          active_request_id: String.t() | nil,
          active_status: AIRequestStatus.t() | nil,
          step_count: non_neg_integer() | nil,
          max_steps: non_neg_integer() | nil,
          gate_token: String.t() | nil,
          gate_expires_at: DateTime.t() | nil,
          pending_proposal: map() | nil,
          last_error: map() | nil,
          token_count: non_neg_integer() | nil,
          codec_version: pos_integer() | nil,
          req_llm_version: String.t() | nil,
          last_message_at: DateTime.t() | nil,
          user_id: non_neg_integer() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          messages: [Message.t()] | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "ai_conversations" do
    field(:skill, :string)
    field(:title, :string)
    field(:status, :string, default: "active")
    field(:active_request_id, :string)
    field(:active_status, AIRequestStatus)
    field(:step_count, :integer, default: 0)
    field(:max_steps, :integer)
    field(:gate_token, :string)
    field(:gate_expires_at, :utc_datetime)
    field(:pending_proposal, :map)
    field(:last_error, :map)
    field(:token_count, :integer, default: 0)
    field(:codec_version, :integer)
    field(:req_llm_version, :string)
    field(:last_message_at, :utc_datetime)

    belongs_to(:user, User)
    belongs_to(:organization, Organization)
    has_many(:messages, Message)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset for creating and updating an agent conversation.
  """
  @spec changeset(Conversation.t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:max_steps, greater_than: 0)
    |> unique_constraint(:active_request_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end
end
