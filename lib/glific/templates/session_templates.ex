defmodule Glific.Templates.SessionTemplate do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{
    Enums.MessageType,
    Messages.MessageMedia,
    Partners.Organization,
    Settings.Language,
    Tags.Tag
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          uuid: Ecto.UUID.t() | nil,
          label: String.t() | nil,
          body: String.t() | nil,
          type: String.t() | nil,
          shortcode: String.t() | nil,
          status: String.t() | nil,
          is_hsm: boolean(),
          number_parameters: non_neg_integer | nil,
          is_source: boolean(),
          is_active: boolean(),
          is_reserved: boolean(),
          language_id: non_neg_integer | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          message_media_id: non_neg_integer | nil,
          message_media: MessageMedia.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_id: non_neg_integer | nil,
          parent: SessionTemplate.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil,
          translations: map() | nil
        }

  @required_fields [
    :label,
    :body,
    :type,
    :language_id,
    :organization_id
  ]
  @optional_fields [
    :shortcode,
    :number_parameters,
    :is_reserved,
    :is_active,
    :is_source,
    :message_media_id,
    :parent_id,
    :is_hsm,
    :uuid,
    :translations,
    :status
  ]

  schema "session_templates" do
    field :uuid, Ecto.UUID, autogenerate: true
    field :label, :string
    field :body, :string
    field :type, MessageType
    field :shortcode, :string

    field :status, :string
    field :is_hsm, :boolean, default: false
    field :number_parameters, :integer

    field :is_source, :boolean, default: false
    field :is_active, :boolean, default: false
    field :is_reserved, :boolean, default: false
    field :translations, :map, default: %{}

    belongs_to :language, Language
    belongs_to :organization, Organization

    belongs_to :message_media, MessageMedia

    belongs_to :parent, SessionTemplate, foreign_key: :parent_id
    has_many :child, SessionTemplate, foreign_key: :parent_id

    many_to_many :tags, Tag,
      join_through: "templates_tags",
      on_replace: :delete,
      join_keys: [template_id: :id, tag_id: :id]

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
    |> foreign_key_constraint(:language_id)
    |> foreign_key_constraint(:parent_id)
    |> unique_constraint([:label, :language_id, :organization_id])
    |> unique_constraint([:shortcode, :language_id, :organization_id])
    |> unique_constraint([:uuid])
  end

  @doc """
  Validation for update HSM session template
  """
  @spec validate_update_hsm(Ecto.Changeset.t(), SessionTemplate.t()) :: Ecto.Changeset.t()
  def validate_update_hsm(changeset, %{:is_hsm => false} = _template) do
    changeset
  end

  @doc """
  Convert SessionTemplate structure to map
  """
  @spec to_minimal_map(SessionTemplate.t()) :: map()
  def to_minimal_map(sessiontemplate) do
    Map.take(sessiontemplate, [:id | @required_fields ++ @optional_fields])
  end

  def validate_update_hsm(changeset, %{:is_hsm => true} = _template) do
    # keeping body, shortcode and status of HSM non editabale by graphql API
    # later on we can add if few other fields should be non editable
    body = changeset.changes[:body]
    shortcode = changeset.changes[:shortcode]
    status = changeset.changes[:status]

    if is_nil(body) && is_nil(shortcode) && is_nil(status) do
      changeset
    else
      add_error(
        changeset,
        :hsm,
        "body/shortcode/status of HSM can not be updated"
      )
    end
  end
end
