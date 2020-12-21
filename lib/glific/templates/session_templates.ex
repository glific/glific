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
          category: String.t() | nil,
          example: String.t() | nil,
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
    :status,
    :category,
    :example
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
    field :category, :string
    field :example, :string

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
  @spec update_changeset(SessionTemplate.t(), map()) :: Ecto.Changeset.t()
  def update_changeset(%{is_hsm: false} = session_template, attrs) do
    session_template
    |> changeset(attrs)
  end

  def update_changeset(%{is_hsm: true, status: "APPROVED"} = session_template, attrs) do
    session_template
    |> cast(attrs, [:is_active, :label])
  end

  def update_changeset(%{is_hsm: true} = session_template, attrs) do
    session_template
    |> cast(attrs, [:is_active, :label])
    |> add_error(
      :hsm,
      "HSM is not approved yet, it can't be modified"
    )
  end

  @doc """
  Convert SessionTemplate structure to map
  """
  @spec to_minimal_map(SessionTemplate.t()) :: map()
  def to_minimal_map(sessiontemplate) do
    Map.take(sessiontemplate, [:id | @required_fields ++ @optional_fields])
  end

  @doc """
  List of available categories provided by whatsapp
  """
  @spec list_whatsapp_hsm_categories() :: [String.t()]
  def list_whatsapp_hsm_categories do
    [
      "ACCOUNT_UPDATE",
      "PAYMENT_UPDATE",
      "PERSONAL_FINANCE_UPDATE",
      "SHIPPING_UPDATE",
      "RESERVATION_UPDATE",
      "ISSUE_RESOLUTION",
      "APPOINTMENT_UPDATE",
      "TRANSPORTATION_UPDATE",
      "TICKET_UPDATE",
      "ALERT_UPDATE",
      "AUTO_REPLY"
    ]
  end
end
