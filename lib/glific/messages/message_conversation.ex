defmodule Glific.Messages.MessageConversation do
  @moduledoc """
  Message conversation are mapped with a message
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
    Messages.Message,
    Partners.Organization
  }

  @required_fields [
    :conversation_id,
    :deduction_type,
    :payload,
    :contact_id,
    :message_id,
    :organization_id
  ]

  @optional_fields [:is_billable]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          conversation_id: String.t() | nil,
          deduction_type: String.t() | nil,
          is_billable: boolean() | false,
          payload: map() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          message_id: non_neg_integer | nil,
          message: Message.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "messages_conversations" do
    field :conversation_id, :string
    field :deduction_type, :string
    field :is_billable, :boolean
    field :payload, :map

    belongs_to :contact, Contact
    belongs_to :message, Message
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(any(), map()) :: Ecto.Changeset.t()
  def changeset(message_conversation, attrs) do
    message_conversation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:organization_id)
  end
end
