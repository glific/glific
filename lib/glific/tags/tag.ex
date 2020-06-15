defmodule Glific.Tags.Tag do
  @moduledoc """
  The minimal wrapper for the base Tag structure
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{Settings.Language, Tags.Tag}
  alias Glific.{Contacts.Contact, Messages.Message}

  @required_fields [:label, :language_id]
  @optional_fields [:description, :is_active, :is_reserved, :is_value, :parent_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          description: String.t() | nil,
          is_active: boolean(),
          is_reserved: boolean(),
          is_value: boolean(),
          language_id: non_neg_integer | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_id: non_neg_integer | nil,
          parent: Tag.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "tags" do
    field :label, :string
    field :description, :string

    field :is_active, :boolean, default: false
    field :is_reserved, :boolean, default: false
    field :is_value, :boolean, default: false

    belongs_to :language, Language

    belongs_to :parent, Tag, foreign_key: :parent_id
    has_many :child, Tag, foreign_key: :parent_id

    many_to_many :contacts, Contact, join_through: "contacts_tags", on_replace: :delete
    many_to_many :messages, Message, join_through: "messages_tags", on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Tag.t(), map()) :: Ecto.Changeset.t()
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:language_id)
    |> foreign_key_constraint(:parent_id)
    |> unique_constraint([:label, :language_id])
  end
end
