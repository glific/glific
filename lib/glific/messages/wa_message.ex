defmodule Glific.Messages.WaMessage do
  @moduledoc false
  use Ecto.Schema

  alias Glific.Enums.{MessageFlow, MessageStatus, MessageType}

  alias Glific.{
    Messages.WaMessage,
    Groups.WAGroup,
    WAGroup.WAManagedPhone,
    Contacts.Contact,
    Messages.MessageMedia,
    Partners.Organization,
    Flows.MessageBroadcast
  }

  import Ecto.Changeset

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          uuid: Ecto.UUID.t() | nil,
          type: String.t() | atom() | nil,
          flow: String.t() | nil,
          label: String.t() | nil,
          status: String.t() | nil,
          bsp_status: String.t() | nil,
          bsp_message_id: String.t() | nil,
          errors: map() | nil,
          message_number: integer(),
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          wa_group_id: non_neg_integer | nil,
          wa_group: WAGroup.t() | Ecto.Association.NotLoaded.t() | nil,
          media_id: non_neg_integer | nil,
          media: MessageMedia.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          body: String.t() | nil,
          context_id: String.t() | nil,
          context_message_id: non_neg_integer | nil,
          context_message: WaMessage.t() | Ecto.Association.NotLoaded.t() | nil,
          message_broadcast_id: non_neg_integer | nil,
          message_broadcast: MessageBroadcast.t() | Ecto.Association.NotLoaded.t() | nil,
          wa_managed_phone_id: non_neg_integer | nil,
          wa_managed_phone: WAManagedPhone.t() | Ecto.Association.NotLoaded.t() | nil,
          send_at: :utc_datetime | nil,
          sent_at: :utc_datetime | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  @required_fields [
    :type,
    :flow,
    :contact_id,
    :organization_id,
    :wa_managed_phone_id,
    :wa_group_id,
    :bsp_status,
    :body,
    :bsp_message_id
  ]
  @optional_fields [
    :uuid,
    :label,
    :status,
    :context_id,
    :context_message_id,
    :message_broadcast_id,
    :errors,
    :send_at,
    :sent_at,
    :updated_at
  ]

  schema "wa_messages" do
    field(:label, :string)
    field(:uuid, Ecto.UUID)
    field(:body, :string)
    field(:type, MessageType)
    field(:flow, MessageFlow)
    field(:status, MessageStatus)
    field(:bsp_status, MessageStatus)
    field(:errors, :map)
    field(:message_number, :integer, default: 0, read_after_writes: true)
    field(:send_at, :utc_datetime)
    field(:sent_at, :utc_datetime)
    field(:context_id, :string)
    field(:bsp_message_id, :string)

    belongs_to(:contact, Contact)
    belongs_to(:wa_managed_phone, WAManagedPhone)
    belongs_to(:media, MessageMedia)

    belongs_to(:wa_group, WAGroup)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime_usec)

    belongs_to(:message_broadcast, MessageBroadcast, foreign_key: :message_broadcast_id)
    belongs_to(:context_message, WaMessage, foreign_key: :context_message_id)
  end

  @spec changeset(WaMessage.t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required_fields ++ @optional_fields, empty_values: [[], nil])
    |> validate_required(@required_fields)
    |> validate_media(message)
    |> unique_constraint([:bsp_message_id, :organization_id])
  end

  @doc false
  # if message type is not text then it should have media id
  @spec changeset(Ecto.Changeset.t(), Message.t()) :: Ecto.Changeset.t()
  defp validate_media(changeset, message) do
    type = changeset.changes[:type]
    media_id = changeset.changes[:media_id] || message.media_id

    cond do
      type in [nil, :text, :location, :list, :quick_reply, :location_request_message] ->
        changeset

      media_id == nil ->
        add_error(changeset, :type, "#{Atom.to_string(type)} message type should have a media id")

      true ->
        changeset
    end
  end
end
