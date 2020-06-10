defmodule Glific.Messages.Message do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{Contacts.Contact, Messages.MessageMedia, Tags.Tag}
  alias Glific.Enums.{MessageFlow, MessageStatus, MessageTypes}

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          type: String.t() | nil,
          flow: String.t() | nil,
          provider_status: String.t() | nil,
          sender: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          receiver: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          media: MessageMedia.t() | Ecto.Association.NotLoaded.t() | nil,
          body: String.t() | nil,
          provider_message_id: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :type,
    :flow,
    :provider_status,
    :sender_id,
    :receiver_id
  ]
  @optional_fields [
    :body,
    :provider_message_id,
    :media_id
  ]

  schema "messages" do
    field :body, :string
    field :flow, MessageFlow
    field :type, MessageTypes
    field :provider_message_id, :string
    field :provider_status, MessageStatus

    belongs_to :sender, Contact
    belongs_to :receiver, Contact
    belongs_to :media, MessageMedia

    many_to_many :tags, Tag, join_through: "messages_tags", on_replace: :delete

    timestamps()
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Message.t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc """
  Convert message structure to map
  """
  @spec to_minimal_map(Message.t()) :: map()
  def to_minimal_map(message) do
    Map.take(message, [:id | @required_fields])
  end
end
