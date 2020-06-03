defmodule Glific.Messages.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{MessageStatusEnum, MessageTypesEnum, MessageFlowEnum}
  alias Glific.{Contacts.Contact}

  @type t() :: %__MODULE__{
          id: non_neg_integer | nil,
          type: String.t() | nil,
          flow: String.t() | nil,
          wa_status: String.t() | nil,
          sender_id: non_neg_integer | nil,
          recipient_id: non_neg_integer | nil,
          body: String.t()| nil,
          wa_message_id: String.t() | nil,
          media_id: non_neg_integer | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }


  @required_fields [
    :type,
    :flow,
    :wa_status,
    :sender_id,
    :recipient_id
  ]
  @optional_fields [
    :body,
    :wa_message_id,
    :media_id
  ]


  schema "messages" do
    field :body, :string
    field :flow, MessageFlowEnum
    field :type, MessageTypesEnum
    field :wa_message_id, :string
    field :wa_status, MessageStatusEnum
    field :media_id, :integer

    belongs_to :sender, Contact
    belongs_to :recipient, Contact
    # belongs_to :media_id, :string
    # belongs_to :media, MessageMedia

    # many_to_many :tags, Tag, join_through: "messages_tags", on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
