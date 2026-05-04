defmodule Glific.AIEvaluations.GoldenQA do
  @moduledoc """
  Schema for Golden QA datasets used in AI evaluations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    AIEvaluations.GoldenQA,
    Partners.Organization
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          name: String.t() | nil,
          dataset_id: non_neg_integer() | nil,
          duplication_factor: non_neg_integer() | nil,
          file_name: String.t() | nil,
          organization_id: non_neg_integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [:name, :dataset_id, :organization_id]
  @optional_fields [:duplication_factor, :file_name]

  schema "golden_qas" do
    field(:name, :string)
    field(:dataset_id, :integer)
    field(:duplication_factor, :integer, default: 1)
    field(:file_name, :string)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset for creating and updating golden QAs.
  """
  @spec changeset(GoldenQA.t(), map()) :: Ecto.Changeset.t()
  def changeset(golden_qa, attrs) do
    golden_qa
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> assoc_constraint(:organization)
    |> unique_constraint([:organization_id, :name])
  end
end
