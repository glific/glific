defmodule Glific.Messages.Message do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{Contacts.Contact, Messages.MessageMedia, Tags.Tag, Users.User}
  alias Glific.Enums.{MessageFlow, MessageStatus, MessageTypes}

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          type: String.t() | nil,
          flow: String.t() | nil,
          provider_status: String.t() | nil,
          message_number: integer(),
          sender: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          receiver: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          media: MessageMedia.t() | Ecto.Association.NotLoaded.t() | nil,
          body: String.t() | nil,
          provider_message_id: String.t() | nil,
          sent_at: :utc_datetime | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :type,
    :flow,
    :sender_id,
    :receiver_id,
    :contact_id
  ]
  @optional_fields [
    :body,
    :provider_status,
    :provider_message_id,
    :media_id,
    :sent_at,
    :user_id
  ]

  schema "messages" do
    field :body, :string
    field :flow, MessageFlow
    field :type, MessageTypes
    field :provider_message_id, :string
    field :provider_status, MessageStatus
    field :sent_at, :utc_datetime
    field :message_number, :integer, default: 0

    belongs_to :sender, Contact
    belongs_to :receiver, Contact
    belongs_to :contact, Contact

    belongs_to :user, User

    belongs_to :media, MessageMedia

    many_to_many :tags, Tag, join_through: "messages_tags", on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Message.t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_media(message)
  end

  @doc """
  Convert message structure to map
  """

  @spec to_minimal_map(Message.t()) :: map()
  def to_minimal_map(message) do
    Map.take(message, [:id | @required_fields ++ @optional_fields])
  end

  @doc false
  # if message type is not text then it should have media id
  @spec changeset(Ecto.Changeset.t(), Message.t()) :: Ecto.Changeset.t()
  defp validate_media(changeset, message) do
    type = changeset.changes[:type]
    media_id = changeset.changes[:media_id] || message.media_id

    cond do
      type == nil ->
        changeset

      type == :text ->
        changeset

      media_id == nil ->
        add_error(changeset, :type, "#{Atom.to_string(type)} message type should have a media id")

      true ->
        changeset
    end
  end
end
