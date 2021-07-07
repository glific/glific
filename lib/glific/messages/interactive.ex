defmodule Glific.Messages.Interactive do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias Glific.{
    Partners.Organization
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          type: String.t() | atom() | nil,
          interactive_content: map() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  @required_fields [
    :label,
    :type,
    :interactive_content,
    :organization_id
  ]

  schema "interactives" do
    field :label, :string
    field :type, :string
    field :interactive_content, :map, default: %{}
    belongs_to :organization, Organization
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Interactive.t(), map()) :: Ecto.Changeset.t()
  def changeset(interactive, attrs) do
    interactive
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:label, :type, :organization_id])
  end
end
