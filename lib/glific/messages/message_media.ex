defmodule Glific.Messages.MessageMedia do
  @moduledoc """
  Message media are mapped with a message
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  # define all the required fields for message media
  @required_fields [
    :url,
    :source_url
  ]

  # define all the optional fields for message media
  @optional_fields [
    :thumbnail,
    :provider_media_id,
    :caption
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          url: String.t() | nil,
          source_url: String.t() | nil,
          caption: String.t() | nil,
          thumbnail: String.t() | nil,
          provider_media_id: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "messages_media" do
    field :url, :string
    field :source_url, :string
    field :thumbnail, :string
    field :caption, :string
    field :provider_media_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(MessageMedia.t(), map()) :: Ecto.Changeset.t()
  def changeset(message_media, attrs) do
    message_media
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
