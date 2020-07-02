defmodule Glific.Contacts.Location do
  @moduledoc """
  Current location of a contact
  """

  alias Glific.{
    Contacts.Contact,
    Contacts.Location,
    Messages.Message
  }

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [
    :contact_id,
    :message_id,
    :longitude,
    :latitude
  ]
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          longitude: float | nil,
          latitude: Float.t() | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          message: Message.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "locations" do
    field :longitude, :float
    field :latitude, :float

    belongs_to :contact, Contact
    belongs_to :message, Message

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Location.t(), map()) :: Ecto.Changeset.t()
  def changeset(location, attrs) do
    location
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
