defmodule Glific.AskGlific.Conversation do
  @moduledoc """
  Schema for storing AskGlific conversations.

  Legacy and inert. This table tracked conversation ids from the retired Dify integration
  (`ask_glific_conversations`); Ask Glific now runs on `Glific.AI.Conversation` /
  `Glific.AI.Message` like every other agent skill, and nothing writes a new row here anymore.
  The table is kept rather than dropped because dropping is irreversible and the row history is
  a record of who used the feature — the Dify-era transcripts these rows pointed at are
  deliberately abandoned along with it (these are staff support chats, not beneficiary data).
  Removing this table entirely is a tracked follow-up, not done here.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Partners.Organization,
    Users.User
  }

  @required_fields [:conversation_id, :user_id, :organization_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          conversation_id: String.t() | nil,
          user_id: non_neg_integer | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "ask_glific_conversations" do
    field :conversation_id, :string

    belongs_to :user, User
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:user_id, :conversation_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end
end
