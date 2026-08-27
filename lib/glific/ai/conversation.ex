defmodule Glific.AI.Conversation do
  @moduledoc """
  A Glific AI chat thread, owned by one user within one organization.

  Groups many `Glific.AI.Message`s, each of which holds its own
  `Glific.AI.Event`s.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Partners.Organization,
    Users.User
  }

  @required_fields [:user_id, :organization_id]
  @optional_fields [:title]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          title: String.t() | nil,
          user_id: non_neg_integer | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "glific_ai_conversations" do
    field :title, :string
    belongs_to :user, User
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end
end
