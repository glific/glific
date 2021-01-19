defmodule Glific.Extensions.Extension do
  @moduledoc """
  The minimal wrapper for the base Extension structure
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Partners.Organization
  }

  @required_fields [:name, :module, :action, :orgsnization_id]
  @optional_fields [:condition, :args]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          module: String.t() | nil,
          condition: String.t() | nil,
          action: String.t() | nil,
          args: [String.t()] | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "extensions" do
    field :name, :string
    field :module, :string
    field :condition, :string
    field :action, :string
    field :args, {:array, :string}, default: []

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Extension.t(), map()) :: Ecto.Changeset.t()
  def changeset(extension, attrs) do
    extension
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name, :organization_id])
  end
end
