defmodule Glific.WAGroup.WAMessage do
  @moduledoc false
  use Ecto.Schema
  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
    Flows.MessageBroadcast,
    Groups.WAGroup,
    Messages.MessageMedia,
    Partners.Organization,
    WAGroup.WAManagedPhone,
    WAGroup.WAMessage
  }

  alias Glific.Enums.{MessageFlow, MessageStatus, MessageType}

  import Ecto.Changeset

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          uuid: Ecto.UUID.t() | nil,
          type: String.t() | atom() | nil,
          flow: String.t() | nil,
          label: String.t() | nil,
          status: String.t() | nil,
          body: String.t() | nil,
          bsp_status: String.t() | nil,
          bsp_id: String.t() | nil,
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
          context_id: String.t() | nil,
          context_message_id: non_neg_integer | nil,
          context_message: WAMessage.t() | Ecto.Association.NotLoaded.t() | nil,
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
    :bsp_status
  ]
  @optional_fields [
    :body,
    :wa_managed_phone_id,
    :wa_group_id,
    :uuid,
    :label,
    :status,
    :context_id,
    :context_message_id,
    :message_broadcast_id,
    :errors,
    :media_id,
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
    field(:bsp_id, :string)

    belongs_to(:contact, Contact)
    belongs_to(:wa_managed_phone, WAManagedPhone)
    belongs_to(:media, MessageMedia)
    belongs_to(:wa_group, WAGroup)
    belongs_to(:organization, Organization)
    belongs_to(:message_broadcast, MessageBroadcast, foreign_key: :message_broadcast_id)
    belongs_to(:context_message, WAMessage, foreign_key: :context_message_id)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Convert message structure to map
  """
  @spec to_minimal_map(WAMessage.t()) :: map()
  def to_minimal_map(message) do
    message
    |> Map.take([:id | @required_fields ++ @optional_fields])
    |> Map.put(:source_url, source_url(message))
  end

  @spec source_url(WAMessage.t()) :: String.t()
  defp source_url(message),
    do:
      if(!message.media || match?(%Ecto.Association.NotLoaded{}, message.media),
        do: nil,
        else: message.media.source_url
      )

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(WAMessage.t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required_fields ++ @optional_fields, empty_values: [[], nil])
    |> validate_required(@required_fields)
    |> validate_media(message)
  end

  @doc false
  # if message type is not text then it should have media id
  @spec changeset(Ecto.Changeset.t(), WAMessage.t()) :: Ecto.Changeset.t()
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
