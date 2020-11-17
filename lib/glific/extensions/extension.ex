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

  @required_fields [:name, :code, :module, :function, :orgsnization_id]
  @optional_fields [:test, :is_valid, :is_pass]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          code: String.t() | nil,
          test: String.t() | nil,
          module: String.t() | nil,
          function: String.t() | nil,
          is_valid: boolean(),
          is_pass: boolean(),
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "extensions" do
    field :name, :string
    field :code, :string
    field :test, :string
    field :module, :string
    field :function, :string

    field :is_valid, :boolean, default: false
    field :is_pass, :boolean, default: false

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
