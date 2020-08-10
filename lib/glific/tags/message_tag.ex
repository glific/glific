defmodule Glific.Tags.MessageTag do
  @moduledoc """
  A file for managing the join table message tags
  """

  alias __MODULE__
  alias Glific.{Messages.Message, Tags.Tag}
  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [:message_id, :tag_id]
  @optional_fields [:value]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          value: String.t() | nil,
          message: Message.t() | Ecto.Association.NotLoaded.t() | nil,
          tag: Tag.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "messages_tags" do
    field :value, :string, default: nil

    belongs_to :message, Message
    belongs_to :tag, Tag
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(MessageTag.t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:message_id, :tag_id])
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:tag_id)
  end
end
