defmodule Glific.AskGlific.Message do
  @moduledoc """
  Schema for storing AskGlific question/answer interactions, used for
  metrics: per-org/user question counts, latency, error rate, and
  rating aggregates.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Partners.Organization,
    Users.User
  }

  @required_fields [:question, :status, :user_id, :organization_id]
  @optional_fields [
    :dify_message_id,
    :conversation_id,
    :answer,
    :latency_ms,
    :error_reason,
    :rating
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          dify_message_id: String.t() | nil,
          conversation_id: String.t() | nil,
          question: String.t() | nil,
          answer: String.t() | nil,
          latency_ms: non_neg_integer | nil,
          status: String.t() | nil,
          error_reason: String.t() | nil,
          rating: String.t() | nil,
          user_id: non_neg_integer | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "ask_glific_messages" do
    field :dify_message_id, :string
    field :conversation_id, :string
    field :question, :string
    field :answer, :string
    field :latency_ms, :integer
    field :status, :string
    field :error_reason, :string
    field :rating, :string

    belongs_to :user, User
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ~w(success error))
    |> validate_inclusion(:rating, ~w(like dislike), message: "must be 'like' or 'dislike'")
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end

  @doc """
  Changeset for updating only the rating after a feedback submission.
  """
  @spec feedback_changeset(t(), map()) :: Ecto.Changeset.t()
  def feedback_changeset(message, attrs) do
    message
    |> cast(attrs, [:rating])
    |> validate_inclusion(:rating, ~w(like dislike), message: "must be 'like' or 'dislike'")
  end
end
