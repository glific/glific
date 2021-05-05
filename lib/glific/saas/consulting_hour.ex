defmodule Glific.Saas.ConsultingHour do
  @moduledoc """
  The table structure to record consulting hours
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo
  }

  # define all the required fields for
  @required_fields [
    :organization_id,
    :participants,
    :staff,
    :when,
    :duration,
    :content
  ]

  # define all the optional fields for organization
  @optional_fields [
    :organization_name,
    :is_billable
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          organization_name: String.t() | nil,
          participants: String.t() | nil,
          staff: String.t() | nil,
          when: DateTime.t() | nil,
          duration: non_neg_integer | nil,
          is_billable: boolean() | true,
          content: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "consulting_hours" do
    field :organization_name, :string
    field :participants, :string
    field :staff, :string

    field :when, :utc_datetime
    field :duration, :integer
    field :content, :string

    field :is_billable, :boolean, default: true

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(ConsultingHour.t(), map()) :: Ecto.Changeset.t()
  def changeset(consulting_hour, attrs) do
    consulting_hour
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:when, :staff, :organization_id],
      message: "Sorry, Consulting hours are already filled for this call"
    )
    |> foreign_key_constraint(:organization_id)
  end

  @doc """
  Create a consulting_hour record
  """
  @spec create_consulting_hour(map()) :: {:ok, ConsultingHour.t()} | {:error, Ecto.Changeset.t()}
  def create_consulting_hour(attrs) do
    %ConsultingHour{}
    |> changeset(Map.put(attrs, :organization_id, attrs.organization_id))
    |> Repo.insert()
  end

  @doc """
  Retrieve a consulting_hour record by clauses
  """
  @spec get_consulting_hour(map()) :: ConsultingHour.t() | nil
  def get_consulting_hour(clauses), do: Repo.get_by(ConsultingHour, clauses)

  @doc """
  Update the consulting_hour record
  """
  @spec update_consulting_hour(ConsultingHour.t(), map()) ::
          {:ok, ConsultingHour.t()} | {:error, Ecto.Changeset.t()}
  def update_consulting_hour(%ConsultingHour{} = consulting_hour, attrs) do
    consulting_hour
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete the consulting_hour record
  """
  @spec delete_consulting_hour(ConsultingHour.t()) ::
          {:ok, ConsultingHour.t()} | {:error, Ecto.Changeset.t()}
  def delete_consulting_hour(%ConsultingHour{} = consulting_hour) do
    Repo.delete(consulting_hour)
  end
end
