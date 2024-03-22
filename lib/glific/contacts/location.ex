defmodule Glific.Contacts.Location do
  @moduledoc """
  Current location of a contact
  """

  alias Glific.WAGroup.WAMessage

  alias Glific.{
    Contacts.Contact,
    Contacts.Location,
    Messages.Message,
    Partners.Organization
  }

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [
    :contact_id,
    :longitude,
    :latitude,
    :organization_id
  ]
  @optional_fields [:message_id, :wa_message_id]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          longitude: float | nil,
          latitude: float | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          message: Message.t() | Ecto.Association.NotLoaded.t() | nil,
          wa_message: WAMessage.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "locations" do
    field :longitude, :float
    field :latitude, :float

    belongs_to :contact, Contact
    belongs_to :message, Message
    belongs_to :organization, Organization
    belongs_to :wa_message, WAMessage
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
    |> validate_message_id()
  end

  @spec validate_message_id(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_message_id(changeset) do
    message_id = Map.get(changeset.changes, :message_id)
    wa_message_id = Map.get(changeset.changes, :wa_message_id)

    case is_nil(message_id) and is_nil(wa_message_id) do
      true ->
        add_error(
          changeset,
          :message_id,
          "both message_id and wa_message_id can't be nil"
        )

      _ ->
        changeset
    end
  end
end
