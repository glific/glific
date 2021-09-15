defmodule Glific.BigQuery.BigQueryJob do
  @moduledoc """
  Book keeping table to keep track of the last job that we processed from the
  messages belonging to the organization
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Partners.Organization
  }

  @required_fields [:organization_id]
  @optional_fields [:table_id, :table, :last_updated_at]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          table_id: non_neg_integer | nil,
          table: String.t(),
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil,
          last_updated_at: :utc_datetime_usec | nil
        }

  schema "bigquery_jobs" do
    field :table_id, :integer, default: 0
    field :table, :string
    field :last_updated_at, :utc_datetime_usec
    belongs_to :organization, Organization
    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(BigQueryJob.t(), map()) :: Ecto.Changeset.t()
  def changeset(search, attrs) do
    search
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
  end
end
