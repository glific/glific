defmodule Glific.Templates.InterativeTemplate do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{
    Partners.Organization
  }

  alias Glific.Enums.InteractiveMessageType

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          type: String.t() | nil,
          interactive_content: map() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :label,
    :type,
    :interactive_content,
    :organization_id
  ]

  schema "interactive_templates" do
    field :label, :string
    field :type, InteractiveMessageType
    field :interactive_content, :map, default: %{}
    belongs_to :organization, Organization
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(InterativeTemplate.t(), map()) :: Ecto.Changeset.t()
  def changeset(interactive, attrs) do
    interactive
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:label, :type, :organization_id])
  end
end
