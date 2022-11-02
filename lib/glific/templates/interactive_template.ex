defmodule Glific.Templates.InteractiveTemplate do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{
    Partners.Organization
  }

  alias Glific.{
    Enums.InteractiveMessageType,
    Settings.Language
  }

  @required_fields [
    :label,
    :type,
    :interactive_content,
    :organization_id,
    :language_id
  ]

  @optional_fields [
    :translations,
    :send_with_title
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          type: String.t() | nil,
          interactive_content: map() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          language_id: non_neg_integer | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          translations: map() | nil,
          send_with_title: boolean(),
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "interactive_templates" do
    field :label, :string
    field :type, InteractiveMessageType
    field :interactive_content, :map, default: %{}
    field :translations, :map, default: %{}
    field :send_with_title, :boolean, default: true

    belongs_to :language, Language
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(InteractiveTemplate.t(), map()) :: Ecto.Changeset.t()
  def changeset(interactive, attrs) do
    interactive
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:label, :type, :organization_id],
      name: :interactive_templates_label_language_id_organization_id_index
    )
    |> unique_constraint([:label, :language_id, :organisation_id],
      name: :interactive_templates_label_type_organization_id_index
    )
    |> foreign_key_constraint(:language_id)
    |> foreign_key_constraint(:organization_id)
  end
end
