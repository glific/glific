defmodule Glific.Templates.SessionTemplate do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{
    Messages.MessageMedia,
    Settings.Language
  }

  alias Glific.Enums.MessageTypes

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          body: String.t() | nil,
          type: String.t() | nil,
          shortcode: String.t() | nil,
          is_source: boolean(),
          is_active: boolean(),
          is_reserved: boolean(),
          language_id: non_neg_integer | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          message_media_id: non_neg_integer | nil,
          message_media: MessageMedia.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_id: non_neg_integer | nil,
          parent: SessionTemplate.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :label,
    :body,
    :type,
    :language_id
  ]
  @optional_fields [
    :shortcode,
    :is_reserved,
    :is_active,
    :is_source,
    :message_media_id,
    :parent_id
  ]

  schema "session_templates" do
    field :label, :string
    field :body, :string
    field :type, MessageTypes
    field :shortcode, :string

    field :is_source, :boolean, default: false
    field :is_active, :boolean, default: false
    field :is_reserved, :boolean, default: false

    belongs_to :language, Language

    belongs_to :message_media, MessageMedia

    belongs_to :parent, SessionTemplate, foreign_key: :parent_id
    has_many :child, SessionTemplate, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(SessionTemplate.t(), map()) :: Ecto.Changeset.t()
  def changeset(session_template, attrs) do
    session_template
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_media(session_template)
    |> foreign_key_constraint(:language_id)
    |> foreign_key_constraint(:parent_id)
    |> unique_constraint([:label, :language_id])
  end

  @doc false
  # if template type is not text then it should have media id
  @spec changeset(Ecto.Changeset.t(), Message.t()) :: Ecto.Changeset.t()
  defp validate_media(changeset, template) do

    type = changeset.changes[:type]
    message_media_id = changeset.changes[:message_media_id] || template.message_media_id

    cond do
      type == nil ->
        changeset

      type == :text ->
        changeset

      message_media_id == nil ->
        add_error(changeset, :type, "#{Atom.to_string(type)} template type should have a message media id")

      true ->
        changeset
    end
  end
end
