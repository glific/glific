defmodule Glific.Search.FullTextSearch do
  @moduledoc """
  The minimal wrapper for the base Search indexer structure
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{Settings.Language, Tags.Tag, Contacts.Contact, Messages.Message}

  @required_fields [:label, :language_id]
  @optional_fields [:description, :is_active, :is_reserved, :parent_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          contact_name: String.t() | nil,
          contact_phone: String.t() | nil,
          tags_label: String.t() | nil,
          document: String.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "full_text_search" do
    field :contact_name, :string
    field :contact_phone, :string
    field :tags_label, :string

    field :document, :string

    belongs_to :contact, Contact

    timestamps()
  end

  @doc """
  Standard changeset pattern we use for all datat types
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
