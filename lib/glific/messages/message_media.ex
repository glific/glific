defmodule Glific.Messages.MessageMedia do
  @moduledoc """
  Message media are mapped with a message
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{
    Enums.MediaType,
    Messages,
    Partners.Organization
  }

  # define all the required fields for message media
  @required_fields [
    :url,
    :source_url,
    :organization_id,
    :media_type
  ]

  # define all the optional fields for message media
  @optional_fields [
    :thumbnail,
    :provider_media_id,
    :caption,
    :gcs_url
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          url: String.t() | nil,
          source_url: String.t() | nil,
          caption: String.t() | nil,
          thumbnail: String.t() | nil,
          provider_media_id: String.t() | nil,
          media_type: String.t() | atom() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil,
          gcs_url: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "messages_media" do
    field(:url, :string)
    field(:source_url, :string)
    field(:thumbnail, :string)
    field(:caption, :string)
    field(:provider_media_id, :string)
    field(:gcs_url, :string)
    field(:media_type, MediaType)

    belongs_to(:organization, Organization)

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
    |> validate_media_url()
  end

  @doc false
  # if message type is not text then it should have media id
  @spec changeset(Ecto.Changeset.t(), Message.t()) :: Ecto.Changeset.t()
  defp validate_media_url(changeset) do
    validate_change(changeset, :url, fn _, url ->
      type = changeset.changes[:media_type] |> to_string()
      results = Messages.validate_media(url, type)
      if results[:is_valid], do: [], else: [{:url, "Invalid url. #{results[:message]}"}]
    end)
  end
end
