defmodule Glific.Contacts.Contact do
  @moduledoc """
  The minimal wrapper for the base Contact structure
  """
  alias Glific.Contacts.Contact

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Enums.ContactStatus
  alias Glific.Settings.Language
  alias Glific.Tags.Tag

  @required_fields [
    :phone,
    :language_id
  ]
  @optional_fields [
    :name,
    :provider_status,
    :status,
    :optin_time,
    :optout_time,
    :last_message_at,
    :settings,
    :fields
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          phone: String.t() | nil,
          status: ContactStatus | nil,
          provider_status: ContactStatus | nil,
          language_id: non_neg_integer | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          optin_time: :utc_datetime | nil,
          optout_time: :utc_datetime | nil,
          last_message_at: :utc_datetime | nil,
          settings: map() | nil,
          fields: map() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "contacts" do
    field :name, :string
    field :phone, :string

    field :status, ContactStatus
    field :provider_status, ContactStatus

    belongs_to :language, Language

    field :optin_time, :utc_datetime
    field :optout_time, :utc_datetime
    field :last_message_at, :utc_datetime

    field :settings, :map
    field :fields, :map

    many_to_many :tags, Tag, join_through: "contacts_tags", on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Contact.t(), map()) :: Ecto.Changeset.t()
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:phone)
  end
end
