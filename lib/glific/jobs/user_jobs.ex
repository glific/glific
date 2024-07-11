defmodule Glific.Jobs.UserJob do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false
  alias __MODULE__

  alias Glific.{
    Partners.Organization
  }

  @required_fields [
    :status,
    :type,
    :total_tasks,
    :tasks_done,
    :organization_id
  ]
  @optional_fields [:errors]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          status: String.t() | nil,
          type: String.t() | nil,
          total_tasks: non_neg_integer | nil,
          tasks_done: non_neg_integer | nil,
          organization_id: non_neg_integer | nil,
          errors: map() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "user_jobs" do
    field(:status, :string, default: "pending")
    field(:type, :string)
    field(:total_tasks, :integer)
    field(:tasks_done, :integer)
    field(:errors, :map, default: %{})

    belongs_to(:organization, Organization, foreign_key: :organization_id)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(UserJob.t(), map()) :: Ecto.Changeset.t()
  def changeset(user_job, attrs) do
    user_job
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
  end
end
