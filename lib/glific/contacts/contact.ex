defmodule Glific.Contacts.Contact do
  @moduledoc """
  The minimal wrapper for the base Contact structure
  """
  alias Glific.Contacts.Contact

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Enums.ContactStatus
  alias Glific.Tags.Tag

  @required_fields [:name, :phone]
  @optional_fields [:provider_status, :status, :optin_time, :optout_time]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          phone: String.t() | nil,
          status: ContactStatus | nil,
          provider_status: ContactStatus | nil,
          optin_time: :utc_datetime | nil,
          optout_time: :utc_datetime | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "contacts" do
    field :name, :string
    field :phone, :string

    field :status, ContactStatus
    field :provider_status, ContactStatus

    field :optin_time, :utc_datetime
    field :optout_time, :utc_datetime

    many_to_many :tags, Tag, join_through: "contacts_tags", on_replace: :delete

    timestamps()
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
