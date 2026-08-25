defmodule Glific.AI.Request do
  @moduledoc """
  One question and every step taken to answer it.

  A request is the unit that has a lifecycle, costs money, and can fail — an
  individual `Glific.AI.Event` is only a fact that happened and has none of those.

  Glific AI answers one question per request at this stage. When a skill can
  invoke another skill, a `parent_request_id` records that nesting.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    AI.Conversation,
    Enums.GlificAIRequestStatus,
    Partners.Organization,
    Users.User
  }

  @required_fields [:conversation_id, :user_id, :organization_id]
  @optional_fields [
    :skill,
    :status,
    :error,
    :model,
    :input_tokens,
    :output_tokens,
    :cost
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          skill: String.t() | nil,
          status: GlificAIRequestStatus.t() | nil,
          error: String.t() | nil,
          model: String.t() | nil,
          input_tokens: non_neg_integer | nil,
          output_tokens: non_neg_integer | nil,
          cost: Decimal.t() | nil,
          conversation_id: non_neg_integer | nil,
          conversation: Conversation.t() | Ecto.Association.NotLoaded.t() | nil,
          user_id: non_neg_integer | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "glific_ai_requests" do
    field :skill, :string
    field :status, GlificAIRequestStatus, default: :pending
    field :error, :string
    field :model, :string

    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cost, :decimal, default: Decimal.new("0")

    belongs_to :conversation, Conversation
    belongs_to :user, User
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(request, attrs) do
    request
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end
end
