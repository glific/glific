defmodule Glific.Messages.Message do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
    Messages.MessageMedia,
    Partners.Organization,
    Tags.Tag,
    Users.User
  }

  alias Glific.Enums.{MessageFlow, MessageStatus, MessageType}

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          uuid: Ecto.UUID.t() | nil,
          type: String.t() | nil,
          is_hsm: boolean | nil,
          flow: String.t() | nil,
          flow_label: String.t() | nil,
          status: String.t() | nil,
          bsp_status: String.t() | nil,
          errors: map() | nil,
          message_number: integer(),
          sender_id: non_neg_integer | nil,
          sender: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          receiver_id: non_neg_integer | nil,
          receiver: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          user_id: non_neg_integer | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          flow_id: non_neg_integer | nil,
          media_id: non_neg_integer | nil,
          media: MessageMedia.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          body: String.t() | nil,
          clean_body: String.t() | nil,
          bsp_message_id: String.t() | nil,
          send_at: :utc_datetime | nil,
          sent_at: :utc_datetime | nil,
          session_uuid: Ecto.UUID.t() | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  @required_fields [
    :type,
    :flow,
    :sender_id,
    :receiver_id,
    :contact_id,
    :organization_id
  ]
  @optional_fields [
    :uuid,
    :body,
    :flow_label,
    :clean_body,
    :is_hsm,
    :status,
    :bsp_status,
    :bsp_message_id,
    :errors,
    :media_id,
    :send_at,
    :sent_at,
    :user_id,
    :flow_id,
    :session_uuid
  ]

  schema "messages" do
    field :uuid, Ecto.UUID
    field :body, :string
    field :flow_label, :string
    field :flow, MessageFlow
    field :type, MessageType
    field :status, MessageStatus

    # we keep the clean version of the body here for easy access by flows
    # and other actors
    field :clean_body, :string, virtual: true

    field :is_hsm, :boolean, default: false

    field :bsp_message_id, :string
    field :bsp_status, MessageStatus
    field :errors, :map, default: %{}
    field :send_at, :utc_datetime
    field :sent_at, :utc_datetime
    field :message_number, :integer, default: 0
    field :session_uuid, Ecto.UUID
    field :flow_id, :integer

    belongs_to :sender, Contact
    belongs_to :receiver, Contact
    belongs_to :contact, Contact
    belongs_to :user, User
    belongs_to :media, MessageMedia
    belongs_to :organization, Organization

    many_to_many :tags, Tag, join_through: "messages_tags", on_replace: :delete

    timestamps(type: :utc_datetime_usec)
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
      type in [nil, :text, :location] ->
        changeset

      media_id == nil ->
        add_error(changeset, :type, "#{Atom.to_string(type)} message type should have a media id")

      true ->
        changeset
    end
  end
end
