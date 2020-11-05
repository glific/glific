defmodule Glific.Tags.TemplateTag do
  @moduledoc """
  A pipe for managing the template tags
  """

  alias __MODULE__

  alias Glific.{
    Tags.Tag,
    Templates.SessionTemplate,
    Partners.Organization
  }

  use Ecto.Schema
  import Ecto.Changeset

  @required_fields [:template_id, :tag_id, :organization_id]
  @optional_fields [:value]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          value: String.t() | nil,
          template: SessionTemplate.t() | Ecto.Association.NotLoaded.t() | nil,
          tag: Tag.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "templates_tags" do
    field :value, :string, default: nil

    belongs_to :template, SessionTemplate
    belongs_to :tag, Tag
    belongs_to :organization, Organization
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(TemplateTag.t(), map()) :: Ecto.Changeset.t()
  def changeset(template, attrs) do
    template
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:template_id, :tag_id])
    |> foreign_key_constraint(:template_id)
    |> foreign_key_constraint(:tag_id)
  end
end
